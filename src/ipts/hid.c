// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Copyright (c) 2022-2023 Dorian Stoll
 *
 * Linux driver for Intel Precise Touch & Stylus
 */

#include <linux/completion.h>
#include <linux/err.h>
#include <linux/gfp.h>
#include <linux/hid.h>
#include <linux/mutex.h>
#include <linux/slab.h>
#include <linux/types.h>

#include "context.h"
#include "desc.h"
#include "eds1.h"
#include "eds2.h"
#include "hid.h"
#include "spec-data.h"
#include "spec-hid.h"

void ipts_hid_enable(struct ipts_context *ipts)
{
	WRITE_ONCE(ipts->hid_active, true);
}

void ipts_hid_disable(struct ipts_context *ipts)
{
	WRITE_ONCE(ipts->hid_active, false);
}

static int ipts_hid_start(struct hid_device *hid)
{
	return 0;
}

static void ipts_hid_stop(struct hid_device *hid)
{
}

static int ipts_hid_parse(struct hid_device *hid)
{
	int ret = 0;
	struct ipts_context *ipts = NULL;

	u8 *buffer = NULL;
	size_t size = 0;

	if (!hid)
		return -ENODEV;

	ipts = hid->driver_data;

	if (!ipts)
		return -EFAULT;

	if (!READ_ONCE(ipts->hid_active))
		return -ENODEV;

	if (ipts->info.intf_eds == 1)
		ret = ipts_eds1_get_descriptor(ipts, &buffer, &size);
	else
		ret = ipts_eds2_get_descriptor(ipts, &buffer, &size);

	if (ret) {
		dev_err(ipts->dev, "Failed to allocate HID descriptor: %d\n", ret);
		return ret;
	}

	ret = hid_parse_report(hid, buffer, size);
	kfree(buffer);

	if (ret) {
		dev_err(ipts->dev, "Failed to parse HID descriptor: %d\n", ret);
		return ret;
	}

	return 0;
}

static int ipts_hid_raw_request(struct hid_device *hid, unsigned char report_id, __u8 *buffer,
				size_t size, unsigned char report_type, int request_type)
{
	struct ipts_context *ipts = NULL;

	if (!hid)
		return -ENODEV;

	ipts = hid->driver_data;

	if (!ipts)
		return -EFAULT;

	if (!READ_ONCE(ipts->hid_active))
		return -ENODEV;

	if (ipts->info.intf_eds == 1) {
		return ipts_eds1_raw_request(ipts, buffer, size, report_id, report_type,
					     request_type);
	} else {
		return ipts_eds2_raw_request(ipts, buffer, size, report_id, report_type,
					     request_type);
	}
}

static struct hid_ll_driver ipts_hid_driver = {
	.start = ipts_hid_start,
	.stop = ipts_hid_stop,
	.open = ipts_hid_start,
	.close = ipts_hid_stop,
	.parse = ipts_hid_parse,
	.raw_request = ipts_hid_raw_request,
};

/*
 * Linux 7.2 rejects input reports that are shorter than their descriptor unless it
 * knows the real buffer size and can pad them. The Makefile detects whether the kernel
 * has hid_safe_input_report(), so the module still builds on older kernels.
 */
static int ipts_hid_input_report(struct ipts_context *ipts, u8 *data, size_t bufsize, u32 size)
{
#ifdef IPTS_HAVE_HID_SAFE_INPUT_REPORT
	return hid_safe_input_report(ipts->hid, HID_INPUT_REPORT, data, bufsize, size, 1);
#else
	return hid_input_report(ipts->hid, HID_INPUT_REPORT, data, size, 1);
#endif
}

int ipts_hid_input_data(struct ipts_context *ipts, u32 buffer)
{
	u8 *temp = NULL;
	struct ipts_hid_header *frame = NULL;
	struct ipts_data_header *header = NULL;

	if (!ipts)
		return -EFAULT;

	if (!ipts->hid)
		return -ENODEV;

	if (!READ_ONCE(ipts->hid_active))
		return -ENODEV;

	header = (struct ipts_data_header *)ipts->resources.data[buffer].address;

	temp = ipts->resources.report.address;
	memset(temp, 0, ipts->resources.report.size);

	if (!header)
		return -EFAULT;

	if (header->size == 0)
		return 0;

	if (header->type == IPTS_DATA_TYPE_HID)
		return ipts_hid_input_report(ipts, header->data,
					     ipts->resources.data[buffer].size - sizeof(*header),
					     header->size);

	if (header->type == IPTS_DATA_TYPE_GET_FEATURES) {
		ipts->feature_report.address = header->data;
		ipts->feature_report.size = header->size;

		complete_all(&ipts->feature_event);
		return 0;
	}

	if (header->type != IPTS_DATA_TYPE_FRAME)
		return 0;

	if (header->size + 3 + sizeof(struct ipts_hid_header) > IPTS_HID_REPORT_DATA_SIZE)
		return -ERANGE;

	/*
	 * Synthesize a HID report matching the devices that natively send HID reports
	 */
	temp[0] = IPTS_HID_REPORT_DATA;

	frame = (struct ipts_hid_header *)&temp[3];
	frame->type = IPTS_HID_FRAME_TYPE_RAW;
	frame->size = header->size + sizeof(*frame);

	memcpy(frame->data, header->data, header->size);

	return ipts_hid_input_report(ipts, temp, ipts->resources.report.size,
				     IPTS_HID_REPORT_DATA_SIZE);
}

int ipts_hid_init(struct ipts_context *ipts, struct ipts_device_info info)
{
	int ret = 0;

	if (!ipts)
		return -EFAULT;

	if (ipts->hid)
		return 0;

	ipts->hid = hid_allocate_device();
	if (IS_ERR(ipts->hid)) {
		int err = PTR_ERR(ipts->hid);

		dev_err(ipts->dev, "Failed to allocate HID device: %d\n", err);
		return err;
	}

	ipts->hid->driver_data = ipts;
	ipts->hid->dev.parent = ipts->dev;
	ipts->hid->ll_driver = &ipts_hid_driver;

	ipts->hid->vendor = info.vendor;
	ipts->hid->product = info.product;
	ipts->hid->group = HID_GROUP_GENERIC;

	snprintf(ipts->hid->name, sizeof(ipts->hid->name), "IPTS %04X:%04X", info.vendor,
		 info.product);

	ret = hid_add_device(ipts->hid);
	if (ret) {
		dev_err(ipts->dev, "Failed to add HID device: %d\n", ret);
		ipts_hid_free(ipts);
		return ret;
	}

	return 0;
}

int ipts_hid_free(struct ipts_context *ipts)
{
	if (!ipts)
		return -EFAULT;

	if (!ipts->hid)
		return 0;

	hid_destroy_device(ipts->hid);
	ipts->hid = NULL;

	return 0;
}
