# SPDX-License-Identifier: GPL-2.0-or-later
#
# Makefile for the IPTS touchscreen driver (out-of-tree build for DKMS)
#

obj-m += ipts.o
ipts-objs := cmd.o
ipts-objs += control.o
ipts-objs += eds1.o
ipts-objs += eds2.o
ipts-objs += hid.o
ipts-objs += main.o
ipts-objs += mei.o
ipts-objs += receiver.o
ipts-objs += resources.o
ipts-objs += thread.o

# Linux 7.2 added hid_safe_input_report(), see hid.c
ifneq ($(shell grep -s hid_safe_input_report $(srctree)/include/linux/hid.h),)
ccflags-y += -DIPTS_HAVE_HID_SAFE_INPUT_REPORT
endif
