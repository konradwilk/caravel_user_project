# SPDX-FileCopyrightText: 2021 Konrad Rzeszutek Wilk
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# SPDX-License-Identifier: Apache-2.0
import cocotb
from cocotb.clock import Clock
from cocotb.binary import BinaryValue
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge;
from cocotb.result import TestSuccess;

@cocotb.test()
async def test_start(dut):
    clock = Clock(dut.clock, 10, units="ns")
    cocotb.fork(clock.start())

    dut.RSTB <= 0
    dut.power1 <= 0;
    dut.power2 <= 0;
    dut.power3 <= 0;
    dut.power4 <= 0;
    dut.uut.mprj.wrapper_sha1.wbs_dat_i.value <= 0;

    dut._log.info("Cycling power");
    await ClockCycles(dut.clock, 8)
    dut.power1 <= 1;
    await ClockCycles(dut.clock, 8)
    dut.power2 <= 1;
    await ClockCycles(dut.clock, 8)
    dut.power3 <= 1;
    await ClockCycles(dut.clock, 8)
    dut.power4 <= 1;

    await ClockCycles(dut.clock, 80)
    dut.RSTB <= 1

    dut._log.info("Waiting for active (This can take a while)");
    # wait for the project to become active
    # wrapper.v has  .active     (la_data_in[32+0])
    # wrapper.c: reg_la1_ena = 0;
    #            reg_la1_data = 1; /* 0x2500,0004 */
    await RisingEdge(dut.uut.mprj.wrapper_sha1.active)
    dut._log.info("Active ON");

async def test_wb(dut, i):

    ack_str = "";
    addr = int(dut.uut.mprj.wrapper_sha1.wbs_adr_i.value);
    ack = int(dut.uut.mprj.wrapper_sha1.wbs_ack_o.value);
    try:
        data = int(dut.uut.mprj.wrapper_sha1.wbs_dat_o.value);
        data_i = int(dut.uut.mprj.wrapper_sha1.wbs_dat_i.value);
    except:
        dut._log.info("%4d %s %s DATA_IN=RAW[%s] DATA_OUT=%s" % (i, hex(addr), ack_str,
                      dut.uut.mprj.wrapper_sha1.wbs_dat_i.value,
                      dut.uut.mprj.wrapper_sha1.wbs_dat_o.value));
        pass

    if (addr >= 0x30000024):
        if (ack == 1):
            ack_str = "ACK";

        dut._log.info("%4d %s %s DATA_IN=%s DATA_OUT=%s" % (i, hex(addr), ack_str,  hex(data_i), hex(data)));

        if (ack == 0):
            return;

        if (addr == 0x30000024): # CTRL_GET_NR
            assert(data == 4);

        if (addr == 0x30000028): # CTRL_GET_ID
            assert(data == 0x53484131);

        if (addr == 0x30000038): # CTRL_PANIC
            assert (data_i == 0x0badf00d); # It is a write..

            raise TestSuccess

@cocotb.test()
async def test_values(dut):
    clock = Clock(dut.clock, 10, units="ns")
    cocotb.fork(clock.start())

    # wait for the reset (
    dut._log.info("Waiting for reset");

    #         /* .reset(la_data_in[0]) */
    # reg_la0_ena = 0; /* 0x2500,0010 */
    # reg_la0_data = 1; /* RST on 0x2500,0000*/

    await RisingEdge(dut.uut.mprj.wrapper_sha1.reset)
    await FallingEdge(dut.uut.mprj.wrapper_sha1.reset)

    dut._log.info("Reset done");

    await ClockCycles(dut.clock,1)

    for i in range(300000):

        await ClockCycles(dut.clock,1)
        await test_wb(dut, i);
