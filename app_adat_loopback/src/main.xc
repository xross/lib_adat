// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

// Example code for ADAT. Note that the adat_tx code can be changed to drive a port
// directly

#include <xs1.h>
#include <xclib.h>
#include "adat_tx.h"
#include "adat_rx.h"
#include "stdio.h"
#include "assert.h"

#define XSIM
#define TRACE

#define MAX_GEN_VAL (1<<24)


buffered out port:32 p_adat_tx = XS1_PORT_1A;
buffered in port:32 p_adat_rx = XS1_PORT_1B;

in port mck = XS1_PORT_1C;

#ifdef XSIM
// Generate Audio Master Clock clos
// must be buffered to meet timing
out buffered port:32 mck_out = XS1_PORT_1D;
#endif

//debug trace port (useful in simulator waveform)
out port trace_data = XS1_PORT_32A;

clock mck_blk = XS1_CLKBLK_2;
clock clk_adat_rx = XS1_CLKBLK_1;

void adatReceiver48000(buffered in port:32 p, chanend oChan);

void receiveAdat(chanend c) {
    set_thread_fast_mode_on();
    // Note The ADAT receiver expects a Audio Master Clock close to 24.576 MHz. See mck_gen for XSIM
    while(1) {
        adatReceiver48000(p_adat_rx, c);
        adatReceiver44100(p_adat_rx, c);   // delete this line if only 48000 required.
    }
}

void collectSamples(chanend c) {
    unsigned expected_data=8;
    unsigned count=8; // first 8 data are thrown away by adat_tx (expected_data is calc from count)
    while(expected_data < MAX_GEN_VAL-1) {
        unsigned head, channels[8];
        head = inuint(c);                    // This will be a header nibble in bits 7..4 and 0001 in the bottom 4 bits
        trace_data <: head;
        for(int i = 0; i < 8; i++) {
            channels[i] = inuint(c);         // This will be 24 bits data in each word, shifted up 4 bits.

#ifdef TRACE
            trace_data <: channels[i];
#endif

            expected_data = expected_data + (1<<(count>>5));

            if(channels[i] != expected_data << 8) {
                printf("Error: Received data 0x%x differs from expected data 0x%x. Correctly received so far %d\n", channels[i], expected_data << 8, count-7);
                assert(0);
            }
            count++;

        }
    }
    printf("Loopback tests PASS. Received %d samples as expected\n", count);


}

void generateData(chanend c_data) {
    unsigned data = 0;
    unsigned count = 0;
    timer tmr;
    unsigned time;

    set_thread_fast_mode_on();

    tmr :> time;
    // delay data gen until adat_rx is ready. This is only to align the expected values for the self-check
    tmr when timerafter(time+4000) :> void;

    outuint(c_data, 512);  // master clock multiplier (1024, 256, or 512)
    outuint(c_data, 0);  // SMUX flag (0, 2, or 4)

    while(data <= MAX_GEN_VAL) {
        data = data + (1<<(count>>5)); // add increasing values to data

        outuint(c_data, data << 8);    // left aligned data (only 24 bits will be used)

        count++;
    }

    printf("Finished sending %d words\n", count);

    outct(c_data, XS1_CT_END);
}


void setupClocks() {

    set_clock_src(mck_blk, mck);
#ifndef XSIM
    set_clock_fall_delay(mck_blk, 7);   // XAI2 board, set to appropriate value for board.
#endif

    set_port_clock(p_adat_tx, mck_blk);
    start_clock(mck_blk);
}

#ifdef XSIM
void mck_gen() {
    // generate clock close to 24.576 MHz
    // Only works for multiplier 512!

    unsigned time;
    unsigned count = 0;

    // gen clock data
    unsigned gen_datas[118];

    // gen clock data
    unsigned gen_data;
    unsigned skip_idx=0;
    unsigned patterns[4] = {0x33333333, 0x66666666, 0xcccccccc, 0x99999999};
    unsigned skip_vals[4] = {0x6, 0xc, 0x8, 0x1};
    for(int i=0; i<118; i++) {
        gen_data = patterns[skip_idx&3];
        if((i & 1) || ((i%20)==0 && i>0)) { // odd indexes (59) plus every 20th (5 in 118), 64 in total
            // 64 / 118*32 = 1 / 59
            gen_data &= 0x0fffffff;
            gen_data |= skip_vals[skip_idx&3] << 28;
            skip_idx++;
        }
        gen_datas[i] = gen_data;
    }

    set_thread_fast_mode_on();

    mck_out <: 0 @ time;

    // stretch clock by loosing 10ns every 16th cycle (40 ns every 64th cycle) -> loose one mck cycle every 64th cycle
    // Resulting average frequency = 25MHz * 63/64 = 24.6094.
    // As close as it gets to 24.576 with 100MHz ref clock.

    while(1) {
        for(int i=0; i<118; i++) {
            mck_out <: gen_datas[i];
        }

        count++; // 16 cycles per iteration
    }
}
#endif

void dummy() {
    while(1);
}

int main(void) {
    chan c_data_tx, c_data_rx;
    par {
        generateData(c_data_tx);
        {
            setupClocks();
            adat_tx(c_data_tx, p_adat_tx);
        }
        receiveAdat(c_data_rx);
        collectSamples(c_data_rx);

#ifdef XSIM
        mck_gen();
#else
        dummy();
#endif

#if 1
        // run 8 thread to test worst case
        dummy();
        dummy();
        dummy();
#endif

    }
    return 0;
}
