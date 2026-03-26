// Copyright (C) 2016-2019 Université catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "aer_out.v" - ODIN AER output link module
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Université catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------


module aer_out #(
	parameter N = 256,
	parameter M = 8
)(

    // Global input ----------------------------------- 
    input  wire           CLK,
    input  wire           RST,
    
    // Inputs from SPI configuration latches ----------
    input  wire           SPI_GATE_ACTIVITY_sync,
    input  wire           SPI_OUT_AER_MONITOR_EN,
    input  wire [  M-1:0] SPI_MONITOR_NEUR_ADDR,
    input  wire [  M-1:0] SPI_MONITOR_SYN_ADDR, 
    input  wire           SPI_AER_SRC_CTRL_nNEUR,
    
    // Neuron data inputs -----------------------------
    input  wire [   14:0] NEUR_STATE_MONITOR,
    input  wire [    6:0] NEUR_EVENT_OUT,
    input  wire           CTRL_NEURMEM_WE, 
    input  wire [  M-1:0] CTRL_NEURMEM_ADDR,
    input  wire           CTRL_NEURMEM_CS,
    
    // Synapse data inputs ----------------------------
    input  wire [   31:0] SYNARRAY_WDATA,
    input  wire           CTRL_SYNARRAY_WE, 
    input  wire [   12:0] CTRL_SYNARRAY_ADDR,
    input  wire           CTRL_SYNARRAY_CS,
    
    // Input from scheduler ---------------------------
    input  wire [   12:0] SCHED_DATA_OUT,
  
    // Input from controller --------------------------
    input  wire           CTRL_AEROUT_POP_NEUR,
    
    // Output to controller ---------------------------
    output reg            AEROUT_CTRL_BUSY,
    
	// Output 8-bit AER link --------------------------
	output reg  [  M-1:0] AEROUT_ADDR, 
	output reg  	      AEROUT_REQ,
	input  wire 	      AEROUT_ACK
);


   reg            AEROUT_ACK_sync_int, AEROUT_ACK_sync, AEROUT_ACK_sync_del; 
   wire           AEROUT_ACK_sync_negedge;
   
   reg  [    7:0] neuron_state_monitor_samp;
   reg  [    3:0] synapse_state_samp;
   wire [   31:0] synapse_state_int;
   wire           neuron_state_event, synapse_state_event, synapse_state_event_cond;
   reg            synapse_state_event_del;
   wire           monitored_neuron_popped;
   
   reg            do_neuron0_transfer, do_neuron1_transfer, do_synapse_transfer;
   
   wire           rst_activity;
   
   
   assign rst_activity = RST || SPI_GATE_ACTIVITY_sync;
   
   assign monitored_neuron_popped  = CTRL_AEROUT_POP_NEUR && (SCHED_DATA_OUT[M-1:0] == SPI_MONITOR_NEUR_ADDR);
   
   assign neuron_state_event       = SPI_OUT_AER_MONITOR_EN && ((CTRL_NEURMEM_CS  && CTRL_NEURMEM_WE  && (CTRL_NEURMEM_ADDR  == SPI_MONITOR_NEUR_ADDR)) || (monitored_neuron_popped && SPI_AER_SRC_CTRL_nNEUR));
   assign synapse_state_event_cond = SPI_OUT_AER_MONITOR_EN &&   CTRL_SYNARRAY_CS && CTRL_SYNARRAY_WE && (CTRL_SYNARRAY_ADDR == {SPI_MONITOR_SYN_ADDR, SPI_MONITOR_NEUR_ADDR[7:3]});
   assign synapse_state_event      = synapse_state_event_cond && !neuron_state_event;

   
   // Sync barrier
   always @(posedge CLK, posedge rst_activity) begin
		if (rst_activity) begin
			AEROUT_ACK_sync_int <= 1'b0;
			AEROUT_ACK_sync	    <= 1'b0;
			AEROUT_ACK_sync_del <= 1'b0;
		end
		else begin
			AEROUT_ACK_sync_int <= AEROUT_ACK;
			AEROUT_ACK_sync	    <= AEROUT_ACK_sync_int;
			AEROUT_ACK_sync_del <= AEROUT_ACK_sync;
		end
	end
    assign AEROUT_ACK_sync_negedge = ~AEROUT_ACK_sync && AEROUT_ACK_sync_del;
    
    
    // Register state bank    
    always @(posedge CLK) begin
		if (neuron_state_event)
            neuron_state_monitor_samp <= NEUR_STATE_MONITOR[7:0];
        else
            neuron_state_monitor_samp <= neuron_state_monitor_samp;
	end
    always @(posedge CLK) begin
		if (synapse_state_event_cond)
            synapse_state_samp <= synapse_state_int[3:0];
        else
            synapse_state_samp <= synapse_state_samp;
	end
    
    assign synapse_state_int = SYNARRAY_WDATA >> ({2'b0,SPI_MONITOR_NEUR_ADDR[2:0]} << 2);
    
    
    // Output AER interface
    always @(posedge CLK, posedge rst_activity) begin
		if (rst_activity) begin
			AEROUT_ADDR             <= 8'b0;
			AEROUT_REQ              <= 1'b0;
            AEROUT_CTRL_BUSY        <= 1'b0;
            do_neuron0_transfer     <= 1'b0;
            do_neuron1_transfer     <= 1'b0;
            do_synapse_transfer     <= 1'b0;
            synapse_state_event_del <= 1'b0;
		end else if (~SPI_OUT_AER_MONITOR_EN) begin
            do_neuron0_transfer     <= 1'b0;
            do_neuron1_transfer     <= 1'b0;
            do_synapse_transfer     <= 1'b0;
            synapse_state_event_del <= 1'b0;
            if ((SPI_AER_SRC_CTRL_nNEUR ? CTRL_AEROUT_POP_NEUR : NEUR_EVENT_OUT[6]) && ~AEROUT_ACK_sync) begin
                AEROUT_ADDR      <= SPI_AER_SRC_CTRL_nNEUR ? SCHED_DATA_OUT[M-1:0] : CTRL_NEURMEM_ADDR;
                AEROUT_REQ       <= 1'b1;
                AEROUT_CTRL_BUSY <= 1'b1;
            end else if (AEROUT_ACK_sync) begin
                AEROUT_ADDR      <= AEROUT_ADDR;
                AEROUT_REQ       <= 1'b0;
                AEROUT_CTRL_BUSY <= 1'b1;
            end else if (AEROUT_ACK_sync_negedge) begin
                AEROUT_ADDR      <= AEROUT_ADDR;
                AEROUT_REQ       <= 1'b0;
                AEROUT_CTRL_BUSY <= 1'b0;
            end else begin
                AEROUT_ADDR      <= AEROUT_ADDR;
                AEROUT_REQ       <= AEROUT_REQ;
                AEROUT_CTRL_BUSY <= AEROUT_CTRL_BUSY;
            end
        end else begin
            if (AEROUT_ACK_sync_negedge) begin
                AEROUT_ADDR             <= AEROUT_ADDR;
                AEROUT_REQ              <= 1'b0;
                AEROUT_CTRL_BUSY        <= do_neuron0_transfer || synapse_state_event_del;
                do_neuron0_transfer     <= 1'b0;
                do_neuron1_transfer     <= do_neuron0_transfer;
                do_synapse_transfer     <= 1'b0;
                synapse_state_event_del <= synapse_state_event_del;
            end else if (AEROUT_ACK_sync) begin
                AEROUT_ADDR             <= AEROUT_ADDR;
                AEROUT_REQ              <= 1'b0;
                AEROUT_CTRL_BUSY        <= 1'b1;
                do_neuron0_transfer     <= do_neuron0_transfer;
                do_neuron1_transfer     <= do_neuron1_transfer;
                do_synapse_transfer     <= do_synapse_transfer;
                synapse_state_event_del <= synapse_state_event_del;
            end else if ((neuron_state_event || synapse_state_event) && !AEROUT_REQ) begin
                AEROUT_ADDR             <= synapse_state_event ? {4'b1111,synapse_state_int[3:0]}
                                                               : {(SPI_AER_SRC_CTRL_nNEUR ? monitored_neuron_popped : NEUR_EVENT_OUT[6]),NEUR_STATE_MONITOR[14:8]};
                AEROUT_REQ              <= 1'b1;
                AEROUT_CTRL_BUSY        <= 1'b1;
                do_neuron0_transfer     <= neuron_state_event;
                do_neuron1_transfer     <= 1'b0;
                do_synapse_transfer     <= synapse_state_event;
                synapse_state_event_del <= synapse_state_event_cond && neuron_state_event;
            end else if (do_neuron1_transfer && !AEROUT_REQ) begin
                AEROUT_ADDR             <= neuron_state_monitor_samp;
                AEROUT_REQ              <= 1'b1;
                AEROUT_CTRL_BUSY        <= 1'b1;
                do_neuron0_transfer     <= 1'b0;
                do_neuron1_transfer     <= 1'b1;
                do_synapse_transfer     <= 1'b0;
                synapse_state_event_del <= synapse_state_event_del;
            end else if (synapse_state_event_del && !AEROUT_REQ) begin
                AEROUT_ADDR             <= {4'b1111,synapse_state_samp};
                AEROUT_REQ              <= 1'b1;
                AEROUT_CTRL_BUSY        <= 1'b1;
                do_neuron0_transfer     <= 1'b0;
                do_neuron1_transfer     <= 1'b0;
                do_synapse_transfer     <= 1'b0;
                synapse_state_event_del <= 1'b0;
            end else begin
                AEROUT_ADDR             <= AEROUT_ADDR;
                AEROUT_REQ              <= AEROUT_REQ;
                AEROUT_CTRL_BUSY        <= AEROUT_CTRL_BUSY;
                do_neuron0_transfer     <= do_neuron0_transfer;
                do_neuron1_transfer     <= do_neuron1_transfer;
                do_synapse_transfer     <= do_synapse_transfer;
                synapse_state_event_del <= synapse_state_event_del;
            end
        end
	end


endmodule 
// Copyright (C) 2016-2019 Université catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "controller.v" - ODIN controller module
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Université catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------


module controller #(
    parameter N = 256,
    parameter M = 8
)(    

    // Global inputs ------------------------------------------
    input  wire           CLK,
    input  wire           RST,
    
    // Inputs from AER ----------------------------------------
    input  wire   [2*M:0] AERIN_ADDR,
    input  wire           AERIN_REQ,
    output reg            AERIN_ACK,
    
    // Control interface for readback -------------------------
    input  wire           CTRL_READBACK_EVENT,
    input  wire           CTRL_PROG_EVENT,
    input  wire [2*M-1:0] CTRL_SPI_ADDR,
    input  wire     [1:0] CTRL_OP_CODE,
    
    // Inputs from SPI configuration registers ----------------
    input  wire           SPI_GATE_ACTIVITY, 
    output reg            SPI_GATE_ACTIVITY_sync,
    input  wire [  M-1:0] SPI_MONITOR_NEUR_ADDR,
	input  wire           SPI_SDSP_ON_SYN_STIM,
    
    // Inputs from scheduler ----------------------------------
    input  wire           SCHED_EMPTY,
    input  wire           SCHED_FULL,
    input  wire           SCHED_BURST_END,
    input  wire    [12:0] SCHED_DATA_OUT,
    
    // Input from AER output ----------------------------------
    input  wire           AEROUT_CTRL_BUSY,
    
    // Outputs to synaptic core -------------------------------
    output reg    [  7:0] CTRL_PRE_EN,
    output reg            CTRL_BIST_REF,
    output reg            CTRL_SYNARRAY_WE,
    output reg            CTRL_NEURMEM_WE,
    output reg    [ 12:0] CTRL_SYNARRAY_ADDR, 
    output reg    [M-1:0] CTRL_NEURMEM_ADDR,
    output reg            CTRL_SYNARRAY_CS,
    output reg            CTRL_NEURMEM_CS,
    
    // Outputs to neurons -------------------------------------
    output reg            CTRL_NEUR_EVENT, 
    output reg            CTRL_NEUR_TREF,
    output reg      [4:0] CTRL_NEUR_VIRTS,
    output reg            CTRL_NEUR_BURST_END,
    
    // Outputs to scheduler -----------------------------------
    output reg            CTRL_SCHED_POP_N,
    output reg    [M-1:0] CTRL_SCHED_ADDR,
    output reg    [  6:0] CTRL_SCHED_EVENT_IN,
    output reg    [  4:0] CTRL_SCHED_VIRTS,
    
    // Output to AER output -----------------------------------
    output wire           CTRL_AEROUT_POP_NEUR
);
    
	//----------------------------------------------------------------------------------
	//	PARAMETERS 
	//----------------------------------------------------------------------------------

	// FSM states 
	localparam WAIT       = 4'd0; 
    localparam W_NEUR     = 4'd1;
    localparam R_NEUR     = 4'd2;
    localparam W_SYN      = 4'd3;
    localparam R_SYN      = 4'd4;
	localparam TREF       = 4'd5;
	localparam BIST       = 4'd6;
    localparam SYNAPSE    = 4'd7;
    localparam PUSH       = 4'd8;
	localparam POP_NEUR   = 4'd9;
    localparam POP_VIRT   = 4'd10;
    localparam WAIT_SPIDN = 4'd11;
    localparam WAIT_REQDN = 4'd12;

	//----------------------------------------------------------------------------------
	//	REGS & WIRES
	//----------------------------------------------------------------------------------
    
    reg          AERIN_REQ_sync_int, AERIN_REQ_sync;
    reg          SPI_GATE_ACTIVITY_sync_int;
    reg          CTRL_READBACK_EVENT_sync_int, CTRL_READBACK_EVENT_sync;
    reg          CTRL_PROG_EVENT_sync_int, CTRL_PROG_EVENT_sync;

    wire         synapse_event, tref_event, bist_event, virt_event, neuron_event;
    
    reg  [ 31:0] ctrl_cnt;
    reg  [  7:0] neur_cnt;
    reg          neur_cnt_inc;
    
    reg  [  3:0] state, nextstate;
    
	//----------------------------------------------------------------------------------
	//	EVENT TYPE DECODING
	//----------------------------------------------------------------------------------

    assign synapse_event  =                     AERIN_ADDR[2*M];
    assign tref_event     = !synapse_event &&  &AERIN_ADDR[M-2:0];
    assign bist_event     = !synapse_event && ~|AERIN_ADDR[M-2:0];
    assign virt_event     = !synapse_event &&  (AERIN_ADDR[2:0] == 3'b001);
    assign neuron_event   = !synapse_event && !tref_event && !bist_event && !virt_event;

	//----------------------------------------------------------------------------------
	//	SYNC BARRIERS FROM AER AND FROM SPI
	//----------------------------------------------------------------------------------
    
   always @(posedge CLK, posedge RST) begin
		if(RST) begin
			AERIN_REQ_sync_int           <= 1'b0;
			AERIN_REQ_sync	             <= 1'b0;
            SPI_GATE_ACTIVITY_sync_int   <= 1'b0;
            SPI_GATE_ACTIVITY_sync       <= 1'b0;
            CTRL_READBACK_EVENT_sync_int <= 1'b0;
            CTRL_READBACK_EVENT_sync     <= 1'b0;
            CTRL_PROG_EVENT_sync_int     <= 1'b0;
            CTRL_PROG_EVENT_sync         <= 1'b0;
		end
		else begin
			AERIN_REQ_sync_int           <= AERIN_REQ;
			AERIN_REQ_sync	             <= AERIN_REQ_sync_int;
            SPI_GATE_ACTIVITY_sync_int   <= SPI_GATE_ACTIVITY;
            SPI_GATE_ACTIVITY_sync       <= SPI_GATE_ACTIVITY_sync_int & ((nextstate == WAIT) | SPI_GATE_ACTIVITY_sync);
            CTRL_READBACK_EVENT_sync_int <= CTRL_READBACK_EVENT;
            CTRL_READBACK_EVENT_sync     <= CTRL_READBACK_EVENT_sync_int;
            CTRL_PROG_EVENT_sync_int     <= CTRL_PROG_EVENT;
            CTRL_PROG_EVENT_sync         <= CTRL_PROG_EVENT_sync_int;
		end
	end
    
	//----------------------------------------------------------------------------------
	//	CONTROL FSM
	//----------------------------------------------------------------------------------
    
    // State register
	always @(posedge CLK, posedge RST)
	begin
		if   (RST) state <= WAIT;
		else       state <= nextstate;
	end
    
	// Next state logic
	always @(*)
		case(state)
			WAIT 		:	if      (AEROUT_CTRL_BUSY)                                                          nextstate = WAIT;
                            else if (SPI_GATE_ACTIVITY_sync)
                                if      (CTRL_PROG_EVENT_sync     && (CTRL_OP_CODE == 2'b01))                   nextstate = W_NEUR;
                                else if (CTRL_READBACK_EVENT_sync && (CTRL_OP_CODE == 2'b01))                   nextstate = R_NEUR;
                                else if (CTRL_PROG_EVENT_sync     && (CTRL_OP_CODE == 2'b10))                   nextstate = W_SYN;
                                else if (CTRL_READBACK_EVENT_sync && (CTRL_OP_CODE == 2'b10))                   nextstate = R_SYN;
                                else                                                                            nextstate = WAIT;
                            else
                                if (SCHED_FULL)
                                    if      (|SCHED_DATA_OUT[12:8])                                             nextstate = POP_VIRT;
                                    else                                                                        nextstate = POP_NEUR;
                                else if (AERIN_REQ_sync && !bist_event)
                                    if      (tref_event)                                                        nextstate = TREF;
                                    else if (synapse_event)                                                     nextstate = SYNAPSE;
                                    else if (virt_event | neuron_event)                                         nextstate = PUSH;
                                    else                                                                        nextstate = WAIT;
                                else if (~SCHED_EMPTY)
                                    if      (|SCHED_DATA_OUT[12:8])                                             nextstate = POP_VIRT;
                                    else                                                                        nextstate = POP_NEUR;
                                else if (AERIN_REQ_sync && bist_event)                                          nextstate = BIST;
                                else                                                                            nextstate = WAIT;
			W_NEUR    	:   if      (ctrl_cnt == 32'd1 )                                                        nextstate = WAIT_SPIDN;
							else					                                                            nextstate = W_NEUR;
			R_NEUR    	:                                                                                       nextstate = WAIT_SPIDN;
			W_SYN    	:   if      (ctrl_cnt == 32'd1 )                                                        nextstate = WAIT_SPIDN;
							else					                                                            nextstate = W_SYN;
			R_SYN    	:                                                                                       nextstate = WAIT_SPIDN;
			TREF    	:   if      (AERIN_ADDR[M-1] ? (ctrl_cnt == 32'd1) : (&neur_cnt && neur_cnt_inc))       nextstate = WAIT_REQDN;
							else					                                                            nextstate = TREF;
            BIST        :   if      (AERIN_ADDR[M-1] ? (ctrl_cnt == 32'h3F) : (&neur_cnt && &ctrl_cnt[5:0]))    nextstate = WAIT_REQDN;
                            else					                                                            nextstate = BIST;
            SYNAPSE     :   if      (ctrl_cnt == 32'd1)                                                         nextstate = WAIT_REQDN;
                            else					                                                            nextstate = SYNAPSE;
            PUSH        :                                                                                       nextstate = WAIT_REQDN;
			POP_NEUR    :   if      (&ctrl_cnt[8:0])                                                            nextstate = WAIT;
							else					                                                            nextstate = POP_NEUR;                
			POP_VIRT    :   if      (~CTRL_SCHED_POP_N)                                                         nextstate = WAIT;
							else					                                                            nextstate = POP_VIRT;
			WAIT_SPIDN 	:   if      (~CTRL_PROG_EVENT_sync && ~CTRL_READBACK_EVENT_sync)                        nextstate = WAIT;
							else					                                                            nextstate = WAIT_SPIDN;
			WAIT_REQDN 	:   if      (~AERIN_REQ_sync)                                                           nextstate = WAIT;
							else					                                                            nextstate = WAIT_REQDN;
			default		:							                                                            nextstate = WAIT;
		endcase 
        
    // Control counter
	always @(posedge CLK, posedge RST)
		if      (RST)               ctrl_cnt <= 32'd0;
        else if (state == WAIT)     ctrl_cnt <= 32'd0;
		else if (!AEROUT_CTRL_BUSY) ctrl_cnt <= ctrl_cnt + 32'd1;
        else                        ctrl_cnt <= ctrl_cnt;
        
    // Time-multiplexed neuron counter
	always @(posedge CLK, posedge RST)
		if      (RST)                                neur_cnt <= 8'd0;
        else if (state == WAIT)                      neur_cnt <= 8'd0;
		else if (neur_cnt_inc && !AEROUT_CTRL_BUSY)  neur_cnt <= neur_cnt + 8'd1;
        else                                         neur_cnt <= neur_cnt;
        
    assign CTRL_AEROUT_POP_NEUR = (state == POP_NEUR) && (neur_cnt == SPI_MONITOR_NEUR_ADDR) && ctrl_cnt[0];
 
 
 
    // Output logic      
    always @(*) begin
    
        if (state == W_NEUR) begin 
            CTRL_SYNARRAY_ADDR  = 13'b0;
            CTRL_SYNARRAY_CS    = 1'b0;
            CTRL_SYNARRAY_WE    = 1'b0;
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_EVENT     = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_PRE_EN         = 8'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            AERIN_ACK           = 1'b0;
            neur_cnt_inc        = 1'b0;  
            
            CTRL_NEURMEM_ADDR   = CTRL_SPI_ADDR[M-1:0];
            CTRL_NEURMEM_CS     = 1'b1;
            if (ctrl_cnt == 32'd0) begin
                CTRL_NEURMEM_WE = 1'b0;
            end else begin
                CTRL_NEURMEM_WE = 1'b1;
            end 
            
        end else if (state == R_NEUR) begin
            CTRL_SYNARRAY_ADDR  = 13'b0;
            CTRL_SYNARRAY_CS    = 1'b0;
            CTRL_SYNARRAY_WE    = 1'b0;
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_EVENT     = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_PRE_EN         = 8'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            AERIN_ACK           = 1'b0;
            neur_cnt_inc        = 1'b0;  
            
            CTRL_NEURMEM_ADDR   = CTRL_SPI_ADDR[M-1:0];
            CTRL_NEURMEM_CS     = 1'b1;
            CTRL_NEURMEM_WE     = 1'b0; 
            
        end else if (state == W_SYN) begin
            CTRL_NEURMEM_ADDR   = 8'b0;
            CTRL_NEURMEM_CS     = 1'b0;
            CTRL_NEURMEM_WE     = 1'b0;
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_EVENT     = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_PRE_EN         = 8'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            AERIN_ACK           = 1'b0;
            neur_cnt_inc        = 1'b0;  
            
            CTRL_SYNARRAY_ADDR  = CTRL_SPI_ADDR[12:0];
            CTRL_SYNARRAY_CS    = 1'b1;
            if (ctrl_cnt == 32'd0) begin
                CTRL_SYNARRAY_WE = 1'b0;
            end else begin
                CTRL_SYNARRAY_WE = 1'b1;
            end 
            
        end else if (state == R_SYN) begin  
            CTRL_NEURMEM_ADDR   = 8'b0;
            CTRL_NEURMEM_CS     = 1'b0;
            CTRL_NEURMEM_WE     = 1'b0;
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_EVENT     = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_PRE_EN         = 8'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            AERIN_ACK           = 1'b0;
            neur_cnt_inc        = 1'b0;  
            
            CTRL_SYNARRAY_ADDR   = CTRL_SPI_ADDR[12:0];
            CTRL_SYNARRAY_CS     = 1'b1;
            CTRL_SYNARRAY_WE     = 1'b0;
            
        end else if (state == TREF) begin
            CTRL_SYNARRAY_ADDR  = 13'b0;
            CTRL_SYNARRAY_CS    = 1'b0;
            CTRL_SYNARRAY_WE    = 1'b0;
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_PRE_EN         = 8'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            AERIN_ACK           = 1'b0;
            
            CTRL_NEURMEM_ADDR   = AERIN_ADDR[M-1] ? AERIN_ADDR[2*M-1:M] : neur_cnt;
            CTRL_NEUR_EVENT     = 1'b1;
            CTRL_NEUR_TREF      = 1'b1;
            CTRL_NEURMEM_CS     = 1'b1;
            if (ctrl_cnt[0] == 1'd0) begin
                CTRL_NEURMEM_WE = 1'b0;
                neur_cnt_inc    = 1'b0;
            end else begin
                CTRL_NEURMEM_WE = 1'b1;
                neur_cnt_inc    = ~AERIN_ADDR[M-1];
            end
            
        end else if (state == BIST) begin
            CTRL_NEURMEM_ADDR   = 8'b0;
            CTRL_NEURMEM_CS     = 1'b0;
            CTRL_NEURMEM_WE     = 1'b0;
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_EVENT     = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            AERIN_ACK           = 1'b0;
            
            CTRL_SYNARRAY_ADDR  = AERIN_ADDR[M-1] ? {AERIN_ADDR[2*M-1:M],ctrl_cnt[5:1]} : {neur_cnt,ctrl_cnt[5:1]};
            CTRL_PRE_EN         = 8'hFF;
            CTRL_BIST_REF       = 1'b1;
            CTRL_SYNARRAY_CS    = 1'b1;
            if (ctrl_cnt[0] == 1'd0) begin
                CTRL_SYNARRAY_WE = 1'b0;
                neur_cnt_inc     = 1'b0;
            end else begin
                CTRL_SYNARRAY_WE = 1'b1;
                neur_cnt_inc     = AERIN_ADDR[M-1] ? 1'b0 : &ctrl_cnt[5:1];
            end 
            
        end else if (state == SYNAPSE) begin 
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            AERIN_ACK           = 1'b0;
            neur_cnt_inc        = 1'b0;
            
            CTRL_SYNARRAY_ADDR  = AERIN_ADDR[2*M-1:3];
            CTRL_NEURMEM_ADDR   = AERIN_ADDR[M-1:0];
            CTRL_PRE_EN         = {7'b0, SPI_SDSP_ON_SYN_STIM} << AERIN_ADDR[2:0];
            CTRL_NEUR_EVENT     = 1'b1;
            CTRL_SYNARRAY_CS    = 1'b1;
            CTRL_NEURMEM_CS     = 1'b1;
            if (ctrl_cnt == 32'd0) begin
                CTRL_SYNARRAY_WE = 1'b0;
                CTRL_NEURMEM_WE  = 1'b0;
            end else begin
                CTRL_SYNARRAY_WE = 1'b1;
                CTRL_NEURMEM_WE  = 1'b1;
            end
        
        end else if (state == PUSH) begin
            CTRL_SYNARRAY_ADDR  = 13'b0;
            CTRL_SYNARRAY_CS    = 1'b0;
            CTRL_SYNARRAY_WE    = 1'b0;
            CTRL_NEURMEM_ADDR   = 8'b0;
            CTRL_NEURMEM_CS     = 1'b0;
            CTRL_NEURMEM_WE     = 1'b0;
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_EVENT     = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_PRE_EN         = 8'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            AERIN_ACK           = 1'b0;
            neur_cnt_inc        = 1'b0;
            
            CTRL_SCHED_VIRTS    = AERIN_ADDR[M-1:M-5];
            CTRL_SCHED_ADDR     = AERIN_ADDR[2*M-1:M];
            CTRL_SCHED_EVENT_IN = 7'h40;

        end else if (state == POP_NEUR) begin  
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            AERIN_ACK           = 1'b0;
            
            CTRL_SYNARRAY_ADDR  = {SCHED_DATA_OUT[M-1:0],neur_cnt[7:3]};
            CTRL_PRE_EN         = (ctrl_cnt[3:0] == 4'b0001) ? 8'hFF : 8'b0;
            CTRL_SYNARRAY_CS    = ~|neur_cnt[2:0];
            CTRL_SYNARRAY_WE    = (ctrl_cnt[3:0] == 4'b0001);
            CTRL_NEURMEM_ADDR   = neur_cnt;  
            CTRL_NEUR_BURST_END = (SCHED_DATA_OUT[M-1:0] == neur_cnt) && SCHED_BURST_END;
            CTRL_SCHED_POP_N    = ~&ctrl_cnt[8:0];
            CTRL_NEUR_EVENT     = 1'b1;
            CTRL_NEURMEM_CS     = 1'b1;
            if (ctrl_cnt[0] == 1'b0) begin
                CTRL_NEURMEM_WE = 1'b0;
                neur_cnt_inc    = 1'b0;
            end else begin
                CTRL_NEURMEM_WE = 1'b1;
                neur_cnt_inc    = 1'b1;    
            end 
        
        end else if (state == POP_VIRT) begin  
            CTRL_SYNARRAY_ADDR  = 13'b0;
            CTRL_SYNARRAY_CS    = 1'b0;
            CTRL_SYNARRAY_WE    = 1'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_PRE_EN         = 8'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            AERIN_ACK           = 1'b0;
            neur_cnt_inc        = 1'b0;
            
            CTRL_NEURMEM_ADDR   = SCHED_DATA_OUT[M-1:0];
            CTRL_NEUR_VIRTS     = SCHED_DATA_OUT[ 12:M];
            CTRL_NEUR_EVENT     = 1'b1;
            CTRL_NEURMEM_CS     = 1'b1;
            if (ctrl_cnt == 32'd0) begin
                CTRL_NEURMEM_WE  = 1'b0;
                CTRL_SCHED_POP_N = 1'b1;
            end else begin
                CTRL_NEURMEM_WE  = 1'b1;
                CTRL_SCHED_POP_N = 1'b0;
            end
        
        end else if (state == WAIT_REQDN) begin
            CTRL_SYNARRAY_ADDR  = 13'b0;
            CTRL_SYNARRAY_CS    = 1'b0;
            CTRL_SYNARRAY_WE    = 1'b0;
            CTRL_NEURMEM_ADDR   = 8'b0;
            CTRL_NEURMEM_CS     = 1'b0;
            CTRL_NEURMEM_WE     = 1'b0;
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_EVENT     = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_PRE_EN         = 8'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            neur_cnt_inc        = 1'b0;
            
            AERIN_ACK           = 1'b1;

        end else begin
            CTRL_SYNARRAY_ADDR  = 13'b0;
            CTRL_SYNARRAY_CS    = 1'b0;
            CTRL_SYNARRAY_WE    = 1'b0;
            CTRL_NEURMEM_ADDR   = 8'b0;
            CTRL_NEURMEM_CS     = 1'b0;
            CTRL_NEURMEM_WE     = 1'b0;
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_EVENT     = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_PRE_EN         = 8'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            AERIN_ACK           = 1'b0;
            neur_cnt_inc        = 1'b0;
        end
    end

    
endmodule

// Copyright (C) 2016-2019 Université catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "fifo.v" - ODIN scheduler FIFO module
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Université catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------


module fifo #(
	parameter width      = 9,
    parameter depth      = 4,
    parameter depth_addr = 2
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              push_req_n,
    input  wire              pop_req_n,
    input  wire [width-1: 0] data_in,
    output reg               empty,
    output wire              full,
    output wire [width-1: 0] data_out
);
  
    reg [width-1:0] mem [0:depth-1]; 

    reg [depth_addr-1:0] write_ptr;
    reg [depth_addr-1:0] read_ptr;
    reg [depth_addr-1:0] fill_cnt;

    genvar i;



    always @(posedge clk, negedge rst_n) begin
        if (!rst_n)
            write_ptr <= 2'b0;
        else if (!push_req_n)
            write_ptr <= write_ptr + {{(depth_addr-1){1'b0}},1'b1};
        else
            write_ptr <= write_ptr;
    end

    always @(posedge clk, negedge rst_n) begin
        if (!rst_n)
            read_ptr <= 2'b0;
        else if (!pop_req_n)
            read_ptr <= read_ptr + {{(depth_addr-1){1'b0}},1'b1};
        else
            read_ptr <= read_ptr;
    end

    always @(posedge clk, negedge rst_n) begin
        if (!rst_n)
            fill_cnt <= 2'b0;
        else if (!push_req_n && pop_req_n && !empty)
            fill_cnt <= fill_cnt + {{(depth_addr-1){1'b0}},1'b1};
        else if (!push_req_n && !pop_req_n)
            fill_cnt <= fill_cnt;
        else if (!pop_req_n && |fill_cnt)
            fill_cnt <= fill_cnt - {{(depth_addr-1){1'b0}},1'b1};
        else
            fill_cnt <= fill_cnt;
    end

    always @(posedge clk, negedge rst_n) begin
        if (!rst_n)
            empty <= 1'b1;
        else if (!push_req_n)
            empty <= 1'b0;
        else if (!pop_req_n)
            empty <= ~|fill_cnt; 
    end

    assign full  =  &fill_cnt;


    generate

        for (i=0; i<depth; i=i+1) begin
            
            always @(posedge clk) begin
                if (!push_req_n && (write_ptr == i))
                    mem[i] <= data_in;
                else 
                    mem[i] <= mem[i];
            end
            
        end
        
    endgenerate

    assign data_out = mem[read_ptr];


endmodule 
// Copyright (C) 2016-2019 Université catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "izh_neuron.v" - ODIN phenomenological Izhikevich neuron update logic (IZH neuron top-level module)
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Université catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------


module izh_neuron #(
	parameter ACC_DEPTH = 11
)( 
    input  wire [          6:0] param_leak_str,          // leakage strength parameter
    input  wire                 param_leak_en,           // leakage enable parameter
    input  wire [          2:0] param_fi_sel,            // accumulator depth parameter for fan-in configuration
    input  wire [          2:0] param_spk_ref,           // number of spikes per burst parameter
    input  wire [          2:0] param_isi_ref,           // inter-spike-interval in burst parameter
    input  wire                 param_reson_sharp_en,    // sharp resonant behavior enable parameter
    input  wire [          2:0] param_thr,               // neuron firing threshold parameter
    input  wire [          2:0] param_rfr,               // neuron refractory period parameter
    input  wire [          2:0] param_dapdel,            // delay for spike latency or DAP parameter
    input  wire                 param_spklat_en,         // spike latency enable parameter
    input  wire                 param_dap_en,            // DAP enable parameter
    input  wire [          2:0] param_stim_thr,          // stimulation threshold (phasic, mixed,...) parameter
    input  wire                 param_phasic_en,         // phasic behavior enable parameter
    input  wire                 param_mixed_en,          // mixed mode behavior enable parameter
    input  wire                 param_class2_en,         // class 2 excitability enable parameter
    input  wire                 param_neg_en,            // negative state enable parameter
    input  wire                 param_rebound_en,        // rebound behavior enable parameter
    input  wire                 param_inhin_en,          // inhibition-induced behavior enable parameter
    input  wire                 param_bist_en,           // bistability behavior enable parameter
    input  wire                 param_reson_en,          // resonant behavior enable parameter
    input  wire                 param_thrvar_en,         // threshold variability and spike frequency adaptation behavior enable parameter
    input  wire                 param_thr_sel_of,        // selection between O (0) and F (1) behaviors parameter (according to Izhikevich behavior numbering)
    input  wire [          3:0] param_thrleak,           // threshold leakage strength parameter
    input  wire                 param_acc_en,            // accommodation behavior enable parameter (requires threshold variability enabled)
    input  wire                 param_ca_en,             // calcium concentration enable parameter                                     [SDSP]
    input  wire [          2:0] param_thetamem,          // membrane threshold parameter                                               [SDSP]
    input  wire [          2:0] param_ca_theta1,         // calcium threshold 1 parameter                                              [SDSP]
    input  wire [          2:0] param_ca_theta2,         // calcium threshold 2 parameter                                              [SDSP]
    input  wire [          2:0] param_ca_theta3,         // calcium threshold 3 parameter                                              [SDSP]
    input  wire [          4:0] param_caleak,            // calcium leakage strength parameter                                         [SDSP]
    input  wire                 param_burst_incr,        // effective threshold and calcium incrementation by burst amount parameter  ([SDSP])
    input  wire [          2:0] param_reson_sharp_amt,   // sharp resonant behavior time constant parameter
    
    input  wire [ACC_DEPTH-1:0] state_inacc,             // input accumulator state from SRAM
    output wire [ACC_DEPTH-1:0] state_inacc_next,        // next input accumulator state to SRAM   
    input  wire                 state_refrac,            // refractory period state from SRAM 
    output wire                 state_refrac_next,       // next refractory period state to SRAM
    input  wire [          3:0] state_core,              // membrane potential state from SRAM 
    output wire [          3:0] state_core_next,         // next membrane potential state to SRAM 
    input  wire [          2:0] state_dapdel_cnt,        // dapdel counter state from SRAM 
    output wire [          2:0] state_dapdel_cnt_next,   // next dapdel counter state to SRAM 
    input  wire [          3:0] state_stim_str,          // stimulation strength state from SRAM 
    output wire [          3:0] state_stim_str_next,     // next stimulation strength state to SRAM 
    input  wire [          3:0] state_stim_str_tmp,      // temporary stimulation strength state from SRAM 
    output wire [          3:0] state_stim_str_tmp_next, // next temporary stimulation strength state to SRAM  
    input  wire                 state_phasic_lock,       // phasic lock state from SRAM
    output wire                 state_phasic_lock_next,  // next phasic lock state to SRAM
    input  wire                 state_mixed_lock,        // mixed lock state from SRAM
    output wire                 state_mixed_lock_next,   // next mixed lock state to SRAM
    input  wire                 state_spkout_done,       // spike sent in current Tref interval state from SRAM
    output wire                 state_spkout_done_next,  // next spike sent in current Tref interval state to SRAM
    input  wire [          1:0] state_stim0_prev,        // zero stimulation monitoring state from SRAM
    output wire [          1:0] state_stim0_prev_next,   // next zero stimulation monitoring state to SRAM
    input  wire [          1:0] state_inhexc_prev,       // inh/exc stimulation monitoring state from SRAM
    output wire [          1:0] state_inhexc_prev_next,  // next inh/exc stimulation monitoring state to SRAM
    input  wire                 state_bist_lock,         // bistability lock state from SRAM
    output wire                 state_bist_lock_next,    // next bistability lock state to SRAM
    input  wire                 state_inhin_lock,        // inhibition-induced lock state from SRAM
    output wire                 state_inhin_lock_next,   // next inhibition-induced lock state to SRAM
    input  wire [          1:0] state_reson_sign,        // resonant sign state from SRAM
    output wire [          1:0] state_reson_sign_next,   // next resonant sign state to SRAM
    input  wire [          3:0] state_thrmod,            // threshold modificator state from SRAM
    output wire [          3:0] state_thrmod_next,       // next threshold modificator state to SRAM
    input  wire [          3:0] state_thrleak_cnt,       // threshold leakage state from SRAM
    output wire [          3:0] state_thrleak_cnt_next,  // next threshold leakage state to SRAM
    input  wire [          2:0] state_calcium,           // calcium concentration state from SRAM     [SDSP]
    output wire [          2:0] state_calcium_next,      // next calcium concentration state to SRAM  [SDSP]
    input  wire [          4:0] state_caleak_cnt,        // calcium leakage state from SRAM           [SDSP]
    output wire [          4:0] state_caleak_cnt_next,   // next calcium leakage state to SRAM        [SDSP]
    input  wire                 state_burst_lock,        // burst lock state from SRAM
    output wire                 state_burst_lock_next,   // next burst lock state to SRAM
    
    input  wire [          2:0] syn_weight,              // synaptic weight
    input  wire                 syn_sign,                // inhibitory (!excitatory) configuration bit
    input  wire                 syn_event,               // synaptic event trigger
    input  wire                 time_ref,                // time reference event trigger
    input  wire                 burst_end,               // end of burst signal
    
    output wire                 v_up_next,               // next SDSP UP condition value              [SDSP]
    output wire                 v_down_next,             // next SDSP DOWN condition value            [SDSP]
    output wire [          6:0] event_out                // neuron spike event output  
);


    wire       event_leak, event_tref;
    wire       event_inh;
    wire       event_exc;

    wire       ovfl_leak;
    wire       ovfl_exc;
    wire       ovfl_inh;

    wire       stim_gt_thr_exc, stim_gt_thr_inh;
    wire       stim_tmp_gt_thr_exc, stim_tmp_gt_thr_inh;
    wire       stim_lone_spike_exc, stim_lone_spike_inh;
    wire       stim_zero;
    wire [3:0] threshold_eff;


    assign event_leak =  syn_event  & time_ref;
    assign event_tref =  event_leak;
    assign event_exc  = ~event_leak & (syn_event & ~syn_sign);
    assign event_inh  = ~event_leak & (syn_event &  syn_sign);

        

    izh_input_accumulator #(
    	.ACC_DEPTH(ACC_DEPTH)
    ) input_accumulator_0 ( 
        .param_leak_str(param_leak_str),
        .param_leak_en(param_leak_en),
        .param_fi_sel(param_fi_sel),
        .state_inacc(state_inacc),
        .syn_weight(syn_weight),
        .event_leak(event_leak),
        .event_exc(event_exc),
        .event_inh(event_inh),
        .state_refrac(state_refrac),
        .state_inacc_next(state_inacc_next),
        .ovfl_leak(ovfl_leak),
        .ovfl_exc(ovfl_exc),
        .ovfl_inh(ovfl_inh)
    );


    izh_stimulation_strength stimulation_strength_0 ( 
        .param_stim_thr(param_stim_thr),
        .state_stim_str(state_stim_str),
        .state_stim_str_tmp(state_stim_str_tmp),
        .state_stim0_prev(state_stim0_prev),
        .state_inhexc_prev(state_inhexc_prev),
        .ovfl_inh(ovfl_inh),
        .ovfl_exc(ovfl_exc),
        .event_tref(event_tref),
        .state_stim_str_next(state_stim_str_next),
        .state_stim_str_tmp_next(state_stim_str_tmp_next),
        .state_stim0_prev_next(state_stim0_prev_next),
        .state_inhexc_prev_next(state_inhexc_prev_next),
        .stim_gt_thr_exc(stim_gt_thr_exc),
        .stim_tmp_gt_thr_exc(stim_tmp_gt_thr_exc),
        .stim_gt_thr_inh(stim_gt_thr_inh),
        .stim_tmp_gt_thr_inh(stim_tmp_gt_thr_inh),
        .stim_lone_spike_exc(stim_lone_spike_exc),
        .stim_lone_spike_inh(stim_lone_spike_inh),
        .stim_zero(stim_zero)
    ); 

    izh_effective_threshold effective_threshold_0 (
        .param_thr(param_thr),
        .param_thrvar_en(param_thrvar_en),
        .param_thr_sel_of(param_thr_sel_of),
        .param_thrleak(param_thrleak),
        .param_acc_en(param_acc_en),
        .param_burst_incr(param_burst_incr),
        .state_thrmod(state_thrmod),
        .state_thrleak_cnt(state_thrleak_cnt),
        .state_stim_str_tmp(state_stim_str_tmp),
        .ovfl_inh(ovfl_inh),
        .ovfl_exc(ovfl_exc),
        .event_tref(event_tref),
        .event_out(event_out),
        .state_thrmod_next(state_thrmod_next),
        .state_thrleak_cnt_next(state_thrleak_cnt_next),
        .threshold_eff(threshold_eff)
    );

    izh_calcium calcium_0 ( 
        .param_ca_en(param_ca_en),
        .param_thetamem(param_thetamem),
        .param_ca_theta1(param_ca_theta1),
        .param_ca_theta2(param_ca_theta2),
        .param_ca_theta3(param_ca_theta3),
        .param_caleak(param_caleak),
        .param_burst_incr(param_burst_incr),
        .state_calcium(state_calcium),
        .state_caleak_cnt(state_caleak_cnt),
        .state_core_next(state_core_next), 
        .event_out(event_out),
        .event_tref(event_tref),
        .v_up_next(v_up_next),
        .v_down_next(v_down_next),
        .state_calcium_next(state_calcium_next),
        .state_caleak_cnt_next(state_caleak_cnt_next)
    );

    izh_neuron_state neuron_state_0 (
        .param_spk_ref(param_spk_ref),
        .param_isi_ref(param_isi_ref),
        .param_rfr(param_rfr),
        .param_dapdel(param_dapdel),
        .param_spklat_en(param_spklat_en),
        .param_dap_en(param_dap_en),
        .param_phasic_en(param_phasic_en),
        .param_mixed_en(param_mixed_en),
        .param_class2_en(param_class2_en),
        .param_neg_en(param_neg_en),
        .param_rebound_en(param_rebound_en),
        .param_inhin_en(param_inhin_en),
        .param_bist_en(param_bist_en),
        .param_reson_en(param_reson_en),
        .param_acc_en(param_acc_en),
        .param_reson_sharp_en(param_reson_sharp_en),
        .param_reson_sharp_amt(param_reson_sharp_amt),
        .state_refrac(state_refrac),
        .state_core(state_core),
        .state_dapdel_cnt(state_dapdel_cnt),
        .state_phasic_lock(state_phasic_lock),
        .state_mixed_lock(state_mixed_lock),
        .state_spkout_done(state_spkout_done),
        .state_bist_lock(state_bist_lock),
        .state_inhin_lock(state_inhin_lock),
        .state_reson_sign(state_reson_sign),
        .state_burst_lock(state_burst_lock),
        .state_stim_str_tmp(state_stim_str_tmp),
        .ovfl_leak(ovfl_leak),
        .ovfl_inh(ovfl_inh),
        .ovfl_exc(ovfl_exc),
        .event_tref(event_tref),
        .burst_end(burst_end),
        .stim_gt_thr_exc(stim_gt_thr_exc),
        .stim_tmp_gt_thr_exc(stim_tmp_gt_thr_exc),
        .stim_gt_thr_inh(stim_gt_thr_inh),
        .stim_tmp_gt_thr_inh(stim_tmp_gt_thr_inh),
        .stim_lone_spike_exc(stim_lone_spike_exc),
        .stim_lone_spike_inh(stim_lone_spike_inh),
        .stim_zero(stim_zero),
        .threshold_eff(threshold_eff),
        .state_refrac_next(state_refrac_next),
        .state_core_next(state_core_next),
        .state_dapdel_cnt_next(state_dapdel_cnt_next),
        .state_phasic_lock_next(state_phasic_lock_next),
        .state_mixed_lock_next(state_mixed_lock_next),
        .state_spkout_done_next(state_spkout_done_next),
        .state_bist_lock_next(state_bist_lock_next),
        .state_inhin_lock_next(state_inhin_lock_next),
        .state_reson_sign_next(state_reson_sign_next),
        .state_burst_lock_next(state_burst_lock_next),
        .event_out(event_out)
    );


endmodule
// Copyright (C) 2016-2019 Université catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "lif_neuron.v" - ODIN leaky integrate-and-fire (LIF) neuron update logic (LIF neuron top-level module)
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Université catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------


module lif_neuron ( 
    input  wire [          6:0] param_leak_str,          // leakage strength parameter
    input  wire                 param_leak_en,           // leakage enable parameter
    input  wire [          7:0] param_thr,               // neuron firing threshold parameter
    input  wire                 param_ca_en,             // calcium concentration enable parameter    [SDSP]
    input  wire [          7:0] param_thetamem,          // membrane threshold parameter              [SDSP]
    input  wire [          2:0] param_ca_theta1,         // calcium threshold 1 parameter             [SDSP]
    input  wire [          2:0] param_ca_theta2,         // calcium threshold 2 parameter             [SDSP]
    input  wire [          2:0] param_ca_theta3,         // calcium threshold 3 parameter             [SDSP]
    input  wire [          4:0] param_caleak,            // calcium leakage strength parameter        [SDSP]
    
    input  wire [          7:0] state_core,              // membrane potential state from SRAM 
    output wire [          7:0] state_core_next,         // next membrane potential state to SRAM
    input  wire [          2:0] state_calcium,           // calcium concentration state from SRAM     [SDSP]
    output wire [          2:0] state_calcium_next,      // next calcium concentration state to SRAM  [SDSP]
    input  wire [          4:0] state_caleak_cnt,        // calcium leakage state from SRAM           [SDSP]
    output wire [          4:0] state_caleak_cnt_next,   // next calcium leakage state to SRAM        [SDSP]
    
    input  wire [          2:0] syn_weight,              // synaptic weight
    input  wire                 syn_sign,                // inhibitory (!excitatory) configuration bit
    input  wire                 syn_event,               // synaptic event trigger
    input  wire                 time_ref,                // time reference event trigger
    
    output wire                 v_up_next,               // next SDSP UP condition value              [SDSP]
    output wire                 v_down_next,             // next SDSP DOWN condition value            [SDSP]
    output wire [          6:0] event_out                // neuron spike event output  
);


    wire       event_leak, event_tref;
    wire       event_inh;
    wire       event_exc;

    assign event_leak =  syn_event  & time_ref;
    assign event_tref =  event_leak;
    assign event_exc  = ~event_leak & (syn_event & ~syn_sign);
    assign event_inh  = ~event_leak & (syn_event &  syn_sign);

        
    lif_calcium calcium_0 ( 
        .param_ca_en(param_ca_en),
        .param_thetamem(param_thetamem),
        .param_ca_theta1(param_ca_theta1),
        .param_ca_theta2(param_ca_theta2),
        .param_ca_theta3(param_ca_theta3),
        .param_caleak(param_caleak),
        .state_calcium(state_calcium),
        .state_caleak_cnt(state_caleak_cnt),
        .state_core_next(state_core_next),
        .spike_out(event_out[6]),
        .event_tref(event_tref),
        .v_up_next(v_up_next),
        .v_down_next(v_down_next),
        .state_calcium_next(state_calcium_next),
        .state_caleak_cnt_next(state_caleak_cnt_next)
    );

    lif_neuron_state neuron_state_0 (
        .param_leak_str(param_leak_str),
        .param_leak_en(param_leak_en),
        .param_thr(param_thr),
        .state_core(state_core),
        .event_leak(event_leak),
        .event_inh(event_inh),
        .event_exc(event_exc),
        .syn_weight(syn_weight),
        .state_core_next(state_core_next),
        .event_out(event_out)
    );


endmodule
// Copyright (C) 2016-2019 Université catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "neuron_core.v" - ODIN neuron core module
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Université catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------


module neuron_core #(
    parameter N = 256,
    parameter M = 8
)(
    
    // Global inputs ------------------------------------------
    input  wire                 RSTN_syncn,
    input  wire                 CLK,
    
    // Inputs from SPI configuration registers ----------------
    input  wire                 SPI_GATE_ACTIVITY_sync,
	input  wire                 SPI_PROPAGATE_UNMAPPED_SYN,
    
    // Synaptic inputs ----------------------------------------
    input  wire [         31:0] SYNARRAY_RDATA,
    input  wire                 SYN_SIGN,
    
    // Inputs from controller ---------------------------------
    input  wire                 CTRL_NEUR_EVENT,
    input  wire                 CTRL_NEUR_TREF,
    input  wire [          4:0] CTRL_NEUR_VIRTS,
    input  wire                 CTRL_NEURMEM_CS,
    input  wire                 CTRL_NEURMEM_WE,
    input  wire [        M-1:0] CTRL_NEURMEM_ADDR,
    input  wire [      2*M-1:0] CTRL_PROG_DATA,
    input  wire [      2*M-1:0] CTRL_SPI_ADDR,
    
    // Inputs from scheduler ----------------------------------
    input  wire                 CTRL_NEUR_BURST_END,
    
    // Outputs ------------------------------------------------
    output wire [        127:0] NEUR_STATE,
    output wire [          6:0] NEUR_EVENT_OUT,
    output reg  [        N-1:0] NEUR_V_UP,
    output reg  [        N-1:0] NEUR_V_DOWN,
    output wire [         14:0] NEUR_STATE_MONITOR
);
    
    // Internal regs and wires definitions

    wire           neur_rstn;
    wire [    2:0] syn_weight;
    wire [   31:0] syn_weight_int;
    wire           syn_sign;
    wire           syn_event;
    wire           time_ref;
    
    wire           LIF_neuron_v_up_next,   IZH_neuron_v_up_next;
    wire           LIF_neuron_v_down_next, IZH_neuron_v_down_next;
    wire [    6:0] LIF_neuron_event_out,   IZH_neuron_event_out;
    
    wire [   15:0] LIF_neuron_next_NEUR_STATE;
    wire [   54:0] IZH_neuron_next_NEUR_STATE;
    
    wire [  127:0] neuron_data_int, neuron_data;
    
    genvar i;

    
    // Processing inputs from the synaptic array and the controller
    
    assign syn_weight_int  = SYNARRAY_RDATA >> ({2'b0,CTRL_NEURMEM_ADDR[2:0]} << 2);
    
    assign syn_weight      = |CTRL_NEUR_VIRTS ? CTRL_NEUR_VIRTS[4:2] : (syn_weight_int[2:0] & {3{syn_weight_int[3] | SPI_PROPAGATE_UNMAPPED_SYN}});
    assign syn_sign        = |CTRL_NEUR_VIRTS ? CTRL_NEUR_VIRTS[1]   : SYN_SIGN;
    assign syn_event       =  CTRL_NEUR_EVENT;
    assign time_ref        = |CTRL_NEUR_VIRTS ? CTRL_NEUR_VIRTS[0]   : CTRL_NEUR_TREF;
    

    // Updated or configured neuron state to be written to the neuron memory

    assign neuron_data_int = NEUR_STATE[0] ? {NEUR_STATE[127: 86], LIF_neuron_next_NEUR_STATE,NEUR_STATE[69:0]}
                                           : {NEUR_STATE[127:125], IZH_neuron_next_NEUR_STATE,NEUR_STATE[69:0]};
    generate
        for (i=0; i<(N>>4); i=i+1) begin
        
            assign neuron_data[M*i+M-1:M*i] = SPI_GATE_ACTIVITY_sync
                                            ? ((i == CTRL_SPI_ADDR[2*M-1:M])
                                                     ? ((CTRL_PROG_DATA[M-1:0] & ~CTRL_PROG_DATA[2*M-1:M]) | (NEUR_STATE[M*i+M-1:M*i] & CTRL_PROG_DATA[2*M-1:M]))
                                                     : NEUR_STATE[M*i+M-1:M*i])
                                            : neuron_data_int[M*i+M-1:M*i];
            
        end
    endgenerate
    

    // Neuron UP/DOWN registers for SDSP online learning

    generate
        for (i=0; i<N; i=i+1) begin
            always @(posedge CLK)
                if (CTRL_NEURMEM_CS && CTRL_NEURMEM_WE && (i == CTRL_NEURMEM_ADDR)) begin
                    NEUR_V_UP[i]   <= NEUR_STATE[0] ? LIF_neuron_v_up_next   : IZH_neuron_v_up_next;
                    NEUR_V_DOWN[i] <= NEUR_STATE[0] ? LIF_neuron_v_down_next : IZH_neuron_v_down_next;
                end else begin
                    NEUR_V_UP[i]   <= NEUR_V_UP[i];
                    NEUR_V_DOWN[i] <= NEUR_V_DOWN[i];
                end
        end
    endgenerate
    

    // Neuron state monitoring

    assign NEUR_STATE_MONITOR = NEUR_STATE[0]
                              ? {LIF_neuron_v_up_next, LIF_neuron_v_down_next, LIF_neuron_next_NEUR_STATE[10:8], 2'b0, LIF_neuron_next_NEUR_STATE[7:0]}
                              : {IZH_neuron_v_up_next, IZH_neuron_v_down_next, IZH_neuron_next_NEUR_STATE[48:46], IZH_neuron_next_NEUR_STATE[37:36], {4'b0,IZH_neuron_next_NEUR_STATE[15:12]}};
    
    // Neuron output spike events

    assign NEUR_EVENT_OUT     = NEUR_STATE[127] ? 7'b0 : ((CTRL_NEURMEM_CS && CTRL_NEURMEM_WE) ? (NEUR_STATE[0] ? LIF_neuron_event_out : IZH_neuron_event_out) : 7'b0);
    
    
    // Neuron update logic for leaky integrate-and-fire (LIF) model
    
    lif_neuron lif_neuron_0 ( 
        .param_leak_str(         NEUR_STATE[0] ? NEUR_STATE[  7:  1] : 7'b0),
        .param_leak_en(          NEUR_STATE[0] ? NEUR_STATE[      8] : 1'b0),
        .param_thr(              NEUR_STATE[0] ? NEUR_STATE[ 16:  9] : 8'b0),
        .param_ca_en(            NEUR_STATE[0] ? NEUR_STATE[     17] : 1'b0),
        .param_thetamem(         NEUR_STATE[0] ? NEUR_STATE[ 25: 18] : 8'b0),
        .param_ca_theta1(        NEUR_STATE[0] ? NEUR_STATE[ 28: 26] : 3'b0),
        .param_ca_theta2(        NEUR_STATE[0] ? NEUR_STATE[ 31: 29] : 3'b0),
        .param_ca_theta3(        NEUR_STATE[0] ? NEUR_STATE[ 34: 32] : 3'b0),
        .param_caleak(           NEUR_STATE[0] ? NEUR_STATE[ 39: 35] : 5'b0),
        
        .state_core(             NEUR_STATE[0] ? NEUR_STATE[ 77: 70] : 8'b0),
        .state_core_next(        LIF_neuron_next_NEUR_STATE[  7:  0]       ),
        .state_calcium(          NEUR_STATE[0] ? NEUR_STATE[ 80: 78] : 3'b0),
        .state_calcium_next(     LIF_neuron_next_NEUR_STATE[ 10:  8]       ),
        .state_caleak_cnt(       NEUR_STATE[0] ? NEUR_STATE[ 85: 81] : 5'b0),
        .state_caleak_cnt_next(  LIF_neuron_next_NEUR_STATE[ 15: 11]       ),
        
        .syn_weight(syn_weight),
        .syn_sign(syn_sign),
        .syn_event(syn_event),
        .time_ref(time_ref),
        
        .v_up_next(LIF_neuron_v_up_next),
        .v_down_next(LIF_neuron_v_down_next),
        .event_out(LIF_neuron_event_out) 
    );
    
    
    // Neuron update logic for phenomenological Izhikevich model

    izh_neuron #(
        .ACC_DEPTH(11)
    ) izh_neuron_0 ( 
        .param_leak_str(         ~NEUR_STATE[0] ? NEUR_STATE[  7:  1] : 7'b0),
        .param_leak_en(          ~NEUR_STATE[0] ? NEUR_STATE[      8] : 1'b0),
        .param_fi_sel(           ~NEUR_STATE[0] ? NEUR_STATE[ 11:  9] : 3'b0),
        .param_spk_ref(          ~NEUR_STATE[0] ? NEUR_STATE[ 14: 12] : 3'b0),
        .param_isi_ref(          ~NEUR_STATE[0] ? NEUR_STATE[ 17: 15] : 3'b0),
        .param_reson_sharp_en(   ~NEUR_STATE[0] ? NEUR_STATE[     18] : 1'b0),
        .param_thr(              ~NEUR_STATE[0] ? NEUR_STATE[ 21: 19] : 3'b0),
        .param_rfr(              ~NEUR_STATE[0] ? NEUR_STATE[ 24: 22] : 3'b0),
        .param_dapdel(           ~NEUR_STATE[0] ? NEUR_STATE[ 27: 25] : 3'b0),
        .param_spklat_en(        ~NEUR_STATE[0] ? NEUR_STATE[     28] : 1'b0),
        .param_dap_en(           ~NEUR_STATE[0] ? NEUR_STATE[     29] : 1'b0),
        .param_stim_thr(         ~NEUR_STATE[0] ? NEUR_STATE[ 32: 30] : 3'b0),
        .param_phasic_en(        ~NEUR_STATE[0] ? NEUR_STATE[     33] : 1'b0),
        .param_mixed_en(         ~NEUR_STATE[0] ? NEUR_STATE[     34] : 1'b0),
        .param_class2_en(        ~NEUR_STATE[0] ? NEUR_STATE[     35] : 1'b0),
        .param_neg_en(           ~NEUR_STATE[0] ? NEUR_STATE[     36] : 1'b0),
        .param_rebound_en(       ~NEUR_STATE[0] ? NEUR_STATE[     37] : 1'b0),
        .param_inhin_en(         ~NEUR_STATE[0] ? NEUR_STATE[     38] : 1'b0),
        .param_bist_en(          ~NEUR_STATE[0] ? NEUR_STATE[     39] : 1'b0),
        .param_reson_en(         ~NEUR_STATE[0] ? NEUR_STATE[     40] : 1'b0),
        .param_thrvar_en(        ~NEUR_STATE[0] ? NEUR_STATE[     41] : 1'b0),
        .param_thr_sel_of(       ~NEUR_STATE[0] ? NEUR_STATE[     42] : 1'b0),
        .param_thrleak(          ~NEUR_STATE[0] ? NEUR_STATE[ 46: 43] : 4'b0),
        .param_acc_en(           ~NEUR_STATE[0] ? NEUR_STATE[     47] : 1'b0),
        .param_ca_en(            ~NEUR_STATE[0] ? NEUR_STATE[     48] : 1'b0),
        .param_thetamem(         ~NEUR_STATE[0] ? NEUR_STATE[ 51: 49] : 3'b0),
        .param_ca_theta1(        ~NEUR_STATE[0] ? NEUR_STATE[ 54: 52] : 3'b0),
        .param_ca_theta2(        ~NEUR_STATE[0] ? NEUR_STATE[ 57: 55] : 3'b0),
        .param_ca_theta3(        ~NEUR_STATE[0] ? NEUR_STATE[ 60: 58] : 3'b0),
        .param_caleak(           ~NEUR_STATE[0] ? NEUR_STATE[ 65: 61] : 5'b0),
        .param_burst_incr(       ~NEUR_STATE[0] ? NEUR_STATE[     66] : 1'b0),
        .param_reson_sharp_amt(  ~NEUR_STATE[0] ? NEUR_STATE[ 69: 67] : 3'b0),
        
        .state_inacc(            ~NEUR_STATE[0] ? NEUR_STATE[ 80: 70] :11'b0),
        .state_inacc_next(        IZH_neuron_next_NEUR_STATE[ 10:  0]       ),
        .state_refrac(           ~NEUR_STATE[0] ? NEUR_STATE[     81] : 1'b0),
        .state_refrac_next(       IZH_neuron_next_NEUR_STATE[     11]       ),
        .state_core(             ~NEUR_STATE[0] ? NEUR_STATE[ 85: 82] : 4'b0),
        .state_core_next(         IZH_neuron_next_NEUR_STATE[ 15: 12]       ),
        .state_dapdel_cnt(       ~NEUR_STATE[0] ? NEUR_STATE[ 88: 86] : 3'b0),
        .state_dapdel_cnt_next(   IZH_neuron_next_NEUR_STATE[ 18: 16]       ),
        .state_stim_str(         ~NEUR_STATE[0] ? NEUR_STATE[ 92: 89] : 4'b0),
        .state_stim_str_next(     IZH_neuron_next_NEUR_STATE[ 22: 19]       ),
        .state_stim_str_tmp(     ~NEUR_STATE[0] ? NEUR_STATE[ 96: 93] : 4'b0),
        .state_stim_str_tmp_next( IZH_neuron_next_NEUR_STATE[ 26: 23]       ),
        .state_phasic_lock(      ~NEUR_STATE[0] ? NEUR_STATE[     97] : 1'b0),
        .state_phasic_lock_next(  IZH_neuron_next_NEUR_STATE[     27]       ),
        .state_mixed_lock(       ~NEUR_STATE[0] ? NEUR_STATE[     98] : 1'b0),
        .state_mixed_lock_next(   IZH_neuron_next_NEUR_STATE[     28]       ),
        .state_spkout_done(      ~NEUR_STATE[0] ? NEUR_STATE[     99] : 1'b0),
        .state_spkout_done_next(  IZH_neuron_next_NEUR_STATE[     29]       ),
        .state_stim0_prev(       ~NEUR_STATE[0] ? NEUR_STATE[101:100] : 2'b0),
        .state_stim0_prev_next(   IZH_neuron_next_NEUR_STATE[ 31: 30]       ),
        .state_inhexc_prev(      ~NEUR_STATE[0] ? NEUR_STATE[103:102] : 2'b0),
        .state_inhexc_prev_next(  IZH_neuron_next_NEUR_STATE[ 33: 32]       ),
        .state_bist_lock(        ~NEUR_STATE[0] ? NEUR_STATE[    104] : 1'b0),
        .state_bist_lock_next(    IZH_neuron_next_NEUR_STATE[     34]       ),
        .state_inhin_lock(       ~NEUR_STATE[0] ? NEUR_STATE[    105] : 1'b0),
        .state_inhin_lock_next(   IZH_neuron_next_NEUR_STATE[     35]       ),
        .state_reson_sign(       ~NEUR_STATE[0] ? NEUR_STATE[107:106] : 2'b0),
        .state_reson_sign_next(   IZH_neuron_next_NEUR_STATE[ 37: 36]       ),
        .state_thrmod(           ~NEUR_STATE[0] ? NEUR_STATE[111:108] : 4'b0),
        .state_thrmod_next(       IZH_neuron_next_NEUR_STATE[ 41: 38]       ),
        .state_thrleak_cnt(      ~NEUR_STATE[0] ? NEUR_STATE[115:112] : 4'b0),
        .state_thrleak_cnt_next(  IZH_neuron_next_NEUR_STATE[ 45: 42]       ),
        .state_calcium(          ~NEUR_STATE[0] ? NEUR_STATE[118:116] : 3'b0),
        .state_calcium_next(      IZH_neuron_next_NEUR_STATE[ 48: 46]       ),
        .state_caleak_cnt(       ~NEUR_STATE[0] ? NEUR_STATE[123:119] : 5'b0),
        .state_caleak_cnt_next(   IZH_neuron_next_NEUR_STATE[ 53: 49]       ),
        .state_burst_lock(       ~NEUR_STATE[0] ? NEUR_STATE[    124] : 1'b0),
        .state_burst_lock_next(   IZH_neuron_next_NEUR_STATE[     54]       ),
        
        .syn_weight(syn_weight),
        .syn_sign(syn_sign),
        .syn_event(syn_event),
        .time_ref(time_ref),
        .burst_end(CTRL_NEUR_BURST_END),
        
        .v_up_next(IZH_neuron_v_up_next),
        .v_down_next(IZH_neuron_v_down_next),
        .event_out(IZH_neuron_event_out)
    );
    

    // Neuron memory wrapper

    SRAM_256x128_wrapper neurarray_0 (       
        
        // Global inputs
        .RSTN       (RSTN_syncn),
        .CK         (CLK),
    
        // Control and data inputs
        .CS         (CTRL_NEURMEM_CS),
        .WE         (CTRL_NEURMEM_WE),
        .A          (CTRL_NEURMEM_ADDR),
        .D          (neuron_data),
        
        // Data output
        .Q          (NEUR_STATE)
    );
    

endmodule




module SRAM_256x128_wrapper (

    // Global inputs
    input          RSTN,                     // Reset_N
    input          CK,                       // Clock (synchronous read/write)

    // Control and data inputs
    input          CS,                       // Chip select (active high)
    input          WE,                       // Write enable (active high)
    input  [  7:0] A,                        // Address bus 
    input  [127:0] D,                        // Data input bus (write)

    // Data output
    output [127:0] Q                         // Data output bus (read)   
);


    /*
     *  Simple behavioral code for simulation, to be replaced by a 256-word 128-bit SRAM macro 
     *  or Block RAM (BRAM) memory with the same format for FPGA implementations.
     */      
        reg [127:0] SRAM[255:0];
        reg [127:0] Qr;
        always @(posedge CK) begin
            Qr <= CS ? SRAM[A] : Qr;
            if (CS & WE) SRAM[A] <= D;
        end
        assign Q = Qr;
    

endmodule
// Copyright (C) 2016-2019 Universit� catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "ODIN.v" - ODIN Spiking Neural Network (SNN) top-level module
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Universit� catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm� 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------


module ODIN #(
	parameter N = 256,
	parameter M = 8
)(
    // Global input     -------------------------------
    input  wire           CLK,
    input  wire           RST,
    
    // SPI slave        -------------------------------
    input  wire           SCK,
    input  wire           MOSI,
    output wire           MISO,

	// Input 16-bit AER -------------------------------
	input  wire [  2*M:0] AERIN_ADDR,
	input  wire           AERIN_REQ,
	output wire 		  AERIN_ACK,

	// Output 8-bit AER -------------------------------
	output wire [  M-1:0] AEROUT_ADDR,
	output wire 	      AEROUT_REQ,
	input  wire 	      AEROUT_ACK
);

    //----------------------------------------------------------------------------------
	//	Internal regs and wires
	//----------------------------------------------------------------------------------

    // Reset and clock
    wire                 RSTN_sync;
    reg                  RST_sync_int, RST_sync, RSTN_syncn;

    // AER output
    wire                 AEROUT_CTRL_BUSY;
    
    // SPI + parameter bank
    wire                 SPI_GATE_ACTIVITY, SPI_GATE_ACTIVITY_sync;
    wire                 SPI_OPEN_LOOP;
    wire [        N-1:0] SPI_SYN_SIGN;
    wire [         19:0] SPI_BURST_TIMEREF;
    wire                 SPI_OUT_AER_MONITOR_EN;
    wire [        M-1:0] SPI_MONITOR_NEUR_ADDR;
    wire [        M-1:0] SPI_MONITOR_SYN_ADDR; 
    wire                 SPI_AER_SRC_CTRL_nNEUR;
    wire                 SPI_UPDATE_UNMAPPED_SYN;
	wire                 SPI_PROPAGATE_UNMAPPED_SYN;
	wire                 SPI_SDSP_ON_SYN_STIM;
    
    // Controller
    wire                 CTRL_READBACK_EVENT;
    wire                 CTRL_PROG_EVENT;
    wire [      2*M-1:0] CTRL_SPI_ADDR;
    wire [          1:0] CTRL_OP_CODE;
    wire [      2*M-1:0] CTRL_PROG_DATA;
    wire [          7:0] CTRL_PRE_EN;
    wire                 CTRL_BIST_REF;
    wire                 CTRL_SYNARRAY_WE;
    wire                 CTRL_NEURMEM_WE;
    wire [         12:0] CTRL_SYNARRAY_ADDR;
    wire [        M-1:0] CTRL_NEURMEM_ADDR;
    wire                 CTRL_SYNARRAY_CS;
    wire                 CTRL_NEURMEM_CS;
    wire                 CTRL_NEUR_EVENT; 
    wire                 CTRL_NEUR_TREF;  
    wire [          4:0] CTRL_NEUR_VIRTS;
    wire                 CTRL_NEUR_BURST_END;
    wire                 CTRL_NEUR_MAPTABLE;
    wire                 CTRL_SCHED_POP_N;
    wire [        M-1:0] CTRL_SCHED_ADDR;
    wire [          6:0] CTRL_SCHED_EVENT_IN;
    wire [          4:0] CTRL_SCHED_VIRTS;
    wire                 CTRL_AEROUT_POP_NEUR;
    
    // Synaptic core
    wire [         31:0] SYNARRAY_RDATA;
    wire [         31:0] SYNARRAY_WDATA;
    wire                 SYN_SIGN;
    
    // Scheduler
    wire                 SCHED_EMPTY;
    wire                 SCHED_FULL;
    wire                 SCHED_BURST_END;
    wire [         12:0] SCHED_DATA_OUT;
    
    // Neuron core
    wire [        127:0] NEUR_STATE;
    wire [         14:0] NEUR_STATE_MONITOR;
    wire [          6:0] NEUR_EVENT_OUT;
    wire [        N-1:0] NEUR_V_UP;
    wire [        N-1:0] NEUR_V_DOWN;
    
    
    //----------------------------------------------------------------------------------
	//	Reset (with double sync barrier)
	//----------------------------------------------------------------------------------
    
    always @(posedge CLK) begin
        RST_sync_int <= RST;
		RST_sync     <= RST_sync_int;
	end
    
    assign RSTN_sync = ~RST_sync;
    
    always @(negedge CLK) begin
        RSTN_syncn <= RSTN_sync;
    end
    
    
    //----------------------------------------------------------------------------------
	//	AER OUT
	//----------------------------------------------------------------------------------
    
    aer_out #(
        .N(N),
        .M(M)
    ) aer_out_0 (

        // Global input ----------------------------------- 
        .CLK(CLK),
        .RST(RST_sync),
        
        // Inputs from SPI configuration latches ----------
        .SPI_GATE_ACTIVITY_sync(SPI_GATE_ACTIVITY_sync),
        .SPI_OUT_AER_MONITOR_EN(SPI_OUT_AER_MONITOR_EN),
        .SPI_MONITOR_NEUR_ADDR(SPI_MONITOR_NEUR_ADDR),
        .SPI_MONITOR_SYN_ADDR(SPI_MONITOR_SYN_ADDR), 
        .SPI_AER_SRC_CTRL_nNEUR(SPI_AER_SRC_CTRL_nNEUR),
        
        // Neuron data inputs -----------------------------
        .NEUR_STATE_MONITOR(NEUR_STATE_MONITOR),
        .NEUR_EVENT_OUT(NEUR_EVENT_OUT),
        .CTRL_NEURMEM_WE(CTRL_NEURMEM_WE), 
        .CTRL_NEURMEM_ADDR(CTRL_NEURMEM_ADDR),
        .CTRL_NEURMEM_CS(CTRL_NEURMEM_CS),
        
        // Synapse data inputs ----------------------------
        .SYNARRAY_WDATA(SYNARRAY_WDATA),
        .CTRL_SYNARRAY_WE(CTRL_SYNARRAY_WE), 
        .CTRL_SYNARRAY_ADDR(CTRL_SYNARRAY_ADDR),
        .CTRL_SYNARRAY_CS(CTRL_SYNARRAY_CS),
        
        // Input from scheduler ---------------------------
        .SCHED_DATA_OUT(SCHED_DATA_OUT),
        
        // Input from controller --------------------------
        .CTRL_AEROUT_POP_NEUR(CTRL_AEROUT_POP_NEUR),
        
        // Output to controller ---------------------------
        .AEROUT_CTRL_BUSY(AEROUT_CTRL_BUSY),
        
        // Output 8-bit AER link --------------------------
        .AEROUT_ADDR(AEROUT_ADDR),
        .AEROUT_REQ(AEROUT_REQ),
        .AEROUT_ACK(AEROUT_ACK)
    );
    
    
    //----------------------------------------------------------------------------------
	//	SPI + parameter bank + clock int/ext handling
	//----------------------------------------------------------------------------------

    spi_slave #(
        .N(N),
        .M(M)
    ) spi_slave_0 (

        // Global inputs ------------------------------------------
        .RST_async(RST),
    
        // SPI slave interface ------------------------------------
        .SCK(SCK),
        .MISO(MISO),
        .MOSI(MOSI),
        
        // Control interface for readback -------------------------
        .CTRL_READBACK_EVENT(CTRL_READBACK_EVENT),
        .CTRL_PROG_EVENT(CTRL_PROG_EVENT),
        .CTRL_SPI_ADDR(CTRL_SPI_ADDR),
        .CTRL_OP_CODE(CTRL_OP_CODE),
        .CTRL_PROG_DATA(CTRL_PROG_DATA),
        .SYNARRAY_RDATA(SYNARRAY_RDATA),
        .NEUR_STATE(NEUR_STATE),
    
        // Configuration registers output -------------------------
        .SPI_GATE_ACTIVITY(SPI_GATE_ACTIVITY),
        .SPI_OPEN_LOOP(SPI_OPEN_LOOP),
        .SPI_SYN_SIGN(SPI_SYN_SIGN),
        .SPI_BURST_TIMEREF(SPI_BURST_TIMEREF),
        .SPI_OUT_AER_MONITOR_EN(SPI_OUT_AER_MONITOR_EN),
        .SPI_AER_SRC_CTRL_nNEUR(SPI_AER_SRC_CTRL_nNEUR),
        .SPI_MONITOR_NEUR_ADDR(SPI_MONITOR_NEUR_ADDR),
        .SPI_MONITOR_SYN_ADDR(SPI_MONITOR_SYN_ADDR),
        .SPI_UPDATE_UNMAPPED_SYN(SPI_UPDATE_UNMAPPED_SYN),
		.SPI_PROPAGATE_UNMAPPED_SYN(SPI_PROPAGATE_UNMAPPED_SYN),
		.SPI_SDSP_ON_SYN_STIM(SPI_SDSP_ON_SYN_STIM)
    );
    
    
    //----------------------------------------------------------------------------------
	//	Controller
	//----------------------------------------------------------------------------------

    controller #(
        .N(N),
        .M(M)
    ) controller_0 (
    
        // Global inputs ------------------------------------------
        .CLK(CLK),
        .RST(RST_sync),
    
        // Inputs from AER ----------------------------------------
        .AERIN_ADDR(AERIN_ADDR),
        .AERIN_REQ(AERIN_REQ),
        .AERIN_ACK(AERIN_ACK),

        // Control interface for readback -------------------------
        .CTRL_READBACK_EVENT(CTRL_READBACK_EVENT),
        .CTRL_PROG_EVENT(CTRL_PROG_EVENT),
        .CTRL_SPI_ADDR(CTRL_SPI_ADDR),
        .CTRL_OP_CODE(CTRL_OP_CODE),
		.SPI_SDSP_ON_SYN_STIM(SPI_SDSP_ON_SYN_STIM),
        
        // Inputs from SPI configuration registers ----------------
        .SPI_GATE_ACTIVITY(SPI_GATE_ACTIVITY),
        .SPI_GATE_ACTIVITY_sync(SPI_GATE_ACTIVITY_sync),
        .SPI_MONITOR_NEUR_ADDR(SPI_MONITOR_NEUR_ADDR),
        
        // Inputs from scheduler ----------------------------------
        .SCHED_EMPTY(SCHED_EMPTY),
        .SCHED_FULL(SCHED_FULL),
        .SCHED_BURST_END(SCHED_BURST_END),
        .SCHED_DATA_OUT(SCHED_DATA_OUT),
        
        // Input from AER output ----------------------------------
        .AEROUT_CTRL_BUSY(AEROUT_CTRL_BUSY),
        
        // Outputs to synaptic core -------------------------------
        .CTRL_PRE_EN(CTRL_PRE_EN),
        .CTRL_BIST_REF(CTRL_BIST_REF),
        .CTRL_SYNARRAY_WE(CTRL_SYNARRAY_WE),
        .CTRL_SYNARRAY_ADDR(CTRL_SYNARRAY_ADDR),
        .CTRL_SYNARRAY_CS(CTRL_SYNARRAY_CS),
        .CTRL_NEURMEM_WE(CTRL_NEURMEM_WE),
        .CTRL_NEURMEM_ADDR(CTRL_NEURMEM_ADDR),
        .CTRL_NEURMEM_CS(CTRL_NEURMEM_CS),
        
        // Outputs to neurons -------------------------------------
        .CTRL_NEUR_EVENT(CTRL_NEUR_EVENT), 
        .CTRL_NEUR_TREF(CTRL_NEUR_TREF),
        .CTRL_NEUR_VIRTS(CTRL_NEUR_VIRTS),
        .CTRL_NEUR_BURST_END(CTRL_NEUR_BURST_END),
        
        // Outputs to scheduler -----------------------------------
        .CTRL_SCHED_POP_N(CTRL_SCHED_POP_N),
        .CTRL_SCHED_ADDR(CTRL_SCHED_ADDR),
        .CTRL_SCHED_EVENT_IN(CTRL_SCHED_EVENT_IN),
        .CTRL_SCHED_VIRTS(CTRL_SCHED_VIRTS),

        // Output to AER output -----------------------------------
        .CTRL_AEROUT_POP_NEUR(CTRL_AEROUT_POP_NEUR)
    );
    
    
    //----------------------------------------------------------------------------------
	//	Scheduler
	//----------------------------------------------------------------------------------

    scheduler #(
        .prio_num(57),
        .N(N),
        .M(M)
    ) scheduler_0 (
    
        // Global inputs ------------------------------------------
        .CLK(CLK),
        .RSTN(RSTN_sync),
    
        // Inputs from controller ---------------------------------
        .CTRL_SCHED_POP_N(CTRL_SCHED_POP_N),
        .CTRL_SCHED_VIRTS(CTRL_SCHED_VIRTS),
        .CTRL_SCHED_ADDR(CTRL_SCHED_ADDR),
        .CTRL_SCHED_EVENT_IN(CTRL_SCHED_EVENT_IN),
        
        // Inputs from neurons ------------------------------------
        .CTRL_NEURMEM_ADDR(CTRL_NEURMEM_ADDR),
        .NEUR_EVENT_OUT(NEUR_EVENT_OUT),
        
        // Inputs from SPI configuration registers ----------------
        .SPI_OPEN_LOOP(SPI_OPEN_LOOP),
        .SPI_BURST_TIMEREF(SPI_BURST_TIMEREF),
        
        // Outputs ------------------------------------------------
        .SCHED_EMPTY(SCHED_EMPTY),
        .SCHED_FULL(SCHED_FULL),
        .SCHED_BURST_END(SCHED_BURST_END),
        .SCHED_DATA_OUT(SCHED_DATA_OUT)
    );
    
    
    //----------------------------------------------------------------------------------
	//	Synaptic core
	//----------------------------------------------------------------------------------
   
    synaptic_core #(
        .N(N),
        .M(M)
    ) synaptic_core_0 (
    
        // Global inputs ------------------------------------------
        .RSTN_syncn(RSTN_syncn),
        .CLK(CLK),

        // Inputs from SPI configuration registers ----------------
        .SPI_GATE_ACTIVITY_sync(SPI_GATE_ACTIVITY_sync),
        .SPI_SYN_SIGN(SPI_SYN_SIGN),
        .SPI_UPDATE_UNMAPPED_SYN(SPI_UPDATE_UNMAPPED_SYN),
        
        // Inputs from controller ---------------------------------
        .CTRL_PRE_EN(CTRL_PRE_EN),
        .CTRL_BIST_REF(CTRL_BIST_REF),
        .CTRL_SYNARRAY_WE(CTRL_SYNARRAY_WE),
        .CTRL_SYNARRAY_ADDR(CTRL_SYNARRAY_ADDR),
        .CTRL_SYNARRAY_CS(CTRL_SYNARRAY_CS),
        .CTRL_PROG_DATA(CTRL_PROG_DATA),
        .CTRL_SPI_ADDR(CTRL_SPI_ADDR),
        
        // Inputs from neurons ------------------------------------
        .NEUR_V_UP(NEUR_V_UP),
        .NEUR_V_DOWN(NEUR_V_DOWN),
        
        // Outputs ------------------------------------------------
        .SYNARRAY_RDATA(SYNARRAY_RDATA),
        .SYNARRAY_WDATA(SYNARRAY_WDATA),
        .SYN_SIGN(SYN_SIGN)
	);
    
    
    //----------------------------------------------------------------------------------
	//	Neural core
	//----------------------------------------------------------------------------------
      
    neuron_core #(
        .N(N),
        .M(M)
    ) neuron_core_0 (
    
        // Global inputs ------------------------------------------
        .RSTN_syncn(RSTN_syncn),
        .CLK(CLK),
        
        // Inputs from SPI configuration registers ----------------
        .SPI_GATE_ACTIVITY_sync(SPI_GATE_ACTIVITY_sync),
        .SPI_PROPAGATE_UNMAPPED_SYN(SPI_PROPAGATE_UNMAPPED_SYN),
		
        // Synaptic inputs ----------------------------------------
        .SYNARRAY_RDATA(SYNARRAY_RDATA),
        .SYN_SIGN(SYN_SIGN),
        
        // Inputs from controller ---------------------------------
        .CTRL_NEUR_EVENT(CTRL_NEUR_EVENT),
        .CTRL_NEUR_TREF(CTRL_NEUR_TREF),
        .CTRL_NEUR_VIRTS(CTRL_NEUR_VIRTS),
        .CTRL_NEURMEM_WE(CTRL_NEURMEM_WE),
        .CTRL_NEURMEM_ADDR(CTRL_NEURMEM_ADDR),
        .CTRL_NEURMEM_CS(CTRL_NEURMEM_CS),
        .CTRL_PROG_DATA(CTRL_PROG_DATA),
        .CTRL_SPI_ADDR(CTRL_SPI_ADDR),
        
        // Inputs from scheduler ----------------------------------
        .CTRL_NEUR_BURST_END(CTRL_NEUR_BURST_END), 
        
        // Outputs ------------------------------------------------
        .NEUR_STATE(NEUR_STATE),
        .NEUR_EVENT_OUT(NEUR_EVENT_OUT),
        .NEUR_V_UP(NEUR_V_UP),
        .NEUR_V_DOWN(NEUR_V_DOWN),
        .NEUR_STATE_MONITOR(NEUR_STATE_MONITOR)
    );
     
        
    
endmodule
// Copyright (C) 2016-2019 Université catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "scheduler.v" - ODIN scheduler module
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Université catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------

 
module scheduler #(
    parameter                   prio_num = 57,
    parameter                   N = 256,
    parameter                   M = 8
)( 

    // Global inputs ------------------------------------------
    input  wire                 CLK,
    input  wire                 RSTN,
    
    // Inputs from controller ---------------------------------
    input  wire                 CTRL_SCHED_POP_N,
    input  wire [          4:0] CTRL_SCHED_VIRTS,
    input  wire [          7:0] CTRL_SCHED_ADDR,
    input  wire [          6:0] CTRL_SCHED_EVENT_IN,
    
    // Inputs from neurons ------------------------------------
    input  wire [        M-1:0] CTRL_NEURMEM_ADDR,
    input  wire [          6:0] NEUR_EVENT_OUT,
    
    // Inputs from SPI configuration registers ----------------
    input  wire                 SPI_OPEN_LOOP,
    input  wire [         19:0] SPI_BURST_TIMEREF,
    
    // Outputs ------------------------------------------------
    output wire                 SCHED_EMPTY,
    output wire                 SCHED_FULL,
    output wire                 SCHED_BURST_END,
    output wire [         12:0] SCHED_DATA_OUT
);


    wire                   spike_in;
    wire [            2:0] spk_ref;
    wire [            3:0] isi_shift;
     
    reg  [  prio_num- 1:0] push_req_burst_n;
    reg                    push_req_n;
    reg  [  prio_num- 1:0] last_spk_in_burst;

    reg  [            7:0] priority_reg; 
    reg  [           19:0] priority_cnt;
    wire                   rst_priority;

    wire [  prio_num- 1:0] push_req_burst_n_fifo;
    wire [  prio_num- 1:0] last_spk_in_burst_fifo;
    wire [  prio_num- 1:0] empty_burst_fifo;
    wire [  prio_num- 1:0] full_burst_fifo;
    wire [9*prio_num- 1:0] data_out_fifo;
    wire                   last_spk_in_burst_int;

    wire                   empty_main;
    wire                   full_main;
    wire [           12:0] data_out_main;
    wire [  prio_num- 2:0] empty_burst_dummy;
    wire [  prio_num- 2:0] full_burst_dummy;
    wire [9*prio_num-10:0] data_out_burst_dummy;
    wire                   empty_burst;
    wire                   full_burst;
    wire [            7:0] data_out_burst;

    reg                    SPI_OPEN_LOOP_sync_int, SPI_OPEN_LOOP_sync;

    wire                   timestamp_next;

    genvar i;


    // Sync barrier from SPI

    always @(posedge CLK, negedge RSTN) begin
        if(~RSTN) begin
            SPI_OPEN_LOOP_sync_int  <= 1'b0;
            SPI_OPEN_LOOP_sync	    <= 1'b0;
        end
        else begin
            SPI_OPEN_LOOP_sync_int  <= SPI_OPEN_LOOP;
            SPI_OPEN_LOOP_sync	    <= SPI_OPEN_LOOP_sync_int;
        end
    end

    // Splitting event_out into FIFO push commands

    assign spike_in  = (~SPI_OPEN_LOOP_sync & NEUR_EVENT_OUT[6]) | CTRL_SCHED_EVENT_IN[6];
    assign spk_ref   = CTRL_SCHED_EVENT_IN[6] ? CTRL_SCHED_EVENT_IN[5:3] : NEUR_EVENT_OUT[5:3];
    assign isi_shift = CTRL_SCHED_EVENT_IN[6] ? ({1'b0, CTRL_SCHED_EVENT_IN[2:0]} + 4'b1) : ({1'b0, NEUR_EVENT_OUT[2:0]} + 4'b1);

    always @(*) begin

        if (spike_in) begin
            if ((spk_ref == 3'd0) || rst_priority) begin
                push_req_burst_n  = {prio_num{1'b1}};
                push_req_n        = 1'b0;
                last_spk_in_burst = {prio_num{1'b0}};
            end else begin 
                push_req_burst_n  = ~(
                                      ({{(prio_num-1){1'b0}},1'b1}            << ( isi_shift   ) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref>=3'd2)} << ((isi_shift*2)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref>=3'd3)} << ((isi_shift*3)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref>=3'd4)} << ((isi_shift*4)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref>=3'd5)} << ((isi_shift*5)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref>=3'd6)} << ((isi_shift*6)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref==3'd7)} << ((isi_shift*7)) ) );
                push_req_n        = 1'b0;
                last_spk_in_burst =  (
                                      ({{(prio_num-1){1'b0}},(spk_ref==3'd1)} << ( isi_shift   ) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref==3'd2)} << ((isi_shift*2)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref==3'd3)} << ((isi_shift*3)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref==3'd4)} << ((isi_shift*4)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref==3'd5)} << ((isi_shift*5)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref==3'd6)} << ((isi_shift*6)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref==3'd7)} << ((isi_shift*7)) ) );
            end
        end else begin
            push_req_burst_n  = {prio_num{1'b1}};
            push_req_n        = 1'b1;
            last_spk_in_burst = {prio_num{1'b0}};
        end
    end


    // Priority

    always @(posedge CLK, posedge rst_priority) begin

        if (rst_priority)
            priority_cnt <= 20'b0;
        else
            if (timestamp_next)
                priority_cnt <= 20'b0;
            else 
                priority_cnt <= priority_cnt + 20'b1;

    end

    assign timestamp_next = (priority_cnt == SPI_BURST_TIMEREF);

    always @(posedge CLK, posedge rst_priority) begin

        if (rst_priority)
            priority_reg <= 8'b0;
        else
            if (timestamp_next)
                if (priority_reg == (prio_num - 1))
                    priority_reg <= 8'b0;
                else 
                    priority_reg <= priority_reg + 8'b1;
            else
                priority_reg  <= priority_reg;

    end

    assign rst_priority = ~RSTN || SPI_OPEN_LOOP_sync || (~|SPI_BURST_TIMEREF);


    // FIFO instances

    fifo #(
        .width(13),
        .depth(32),
        .depth_addr(5)
    ) fifo_spike_0 (
        .clk(CLK),
        .rst_n(RSTN),
        .push_req_n(full_main | push_req_n),
        .pop_req_n(empty_main | ~empty_burst | CTRL_SCHED_POP_N),
        .data_in(CTRL_SCHED_EVENT_IN[6] ? {CTRL_SCHED_VIRTS,CTRL_SCHED_ADDR} : {5'b0,CTRL_NEURMEM_ADDR}),
        .empty(empty_main),
        .full(full_main),
        .data_out(data_out_main)
    );

    generate

        for (i=0; i<prio_num; i=i+1) begin
        
            fifo #(
                .width(9),
                .depth(4),
                .depth_addr(5)
            ) fifo_burst (
                .clk(CLK),
                .rst_n(~rst_priority),
                .push_req_n(full_burst_fifo[i] | push_req_burst_n_fifo[i]),//~(~full_burst_fifo[i] & push_req_burst_n_fifo[i])),
                .pop_req_n(~(~empty_burst_fifo[i] & (i == priority_reg)) | CTRL_SCHED_POP_N),
                .data_in({last_spk_in_burst_fifo[i],CTRL_NEURMEM_ADDR}),
                .empty(empty_burst_fifo[i]), 
                .full(full_burst_fifo[i]),
                .data_out(data_out_fifo[9*i+8:9*i])
            );
                  
        end
        
    endgenerate

    assign push_req_burst_n_fifo  = (push_req_burst_n  << priority_reg) | (push_req_burst_n  >> (prio_num - priority_reg));
    assign last_spk_in_burst_fifo = (last_spk_in_burst << priority_reg) | (last_spk_in_burst >> (prio_num - priority_reg));  


    // Output selection

    assign {empty_burst_dummy,empty_burst}                             = empty_burst_fifo >> priority_reg;
    assign {full_burst_dummy,full_burst}                               = full_burst_fifo >> priority_reg;
    assign {data_out_burst_dummy,last_spk_in_burst_int,data_out_burst} = data_out_fifo >> (9*priority_reg);

    assign SCHED_DATA_OUT                                              = empty_burst ? data_out_main : {5'b0,data_out_burst};
    assign SCHED_BURST_END                                             = empty_burst ? 1'b0 : last_spk_in_burst_int;
    assign SCHED_EMPTY                                                 = empty_main && empty_burst;
    assign SCHED_FULL                                                  = full_main;



endmodule
// Copyright (C) 2016-2019 Université catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "sdsp_update.v" - ODIN SDSP update logic module
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Université catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------


module sdsp_update #(
    parameter WIDTH = 3
)(
    // Inputs
        // General
    input  wire             SYN_PRE,
    input  wire             SYN_BIST_REF,
        // From neuron
    input  wire             V_UP,
    input  wire             V_DOWN,    
        // From SRAM
    input  wire [WIDTH:0] WSYN_CURR,
    
	// Output
	output reg  [WIDTH:0] WSYN_NEW
);
    
    
    wire w_lt_half;
    wire do_up, do_down;
    wire overflow;
    
    assign w_lt_half = SYN_PRE & ~WSYN_CURR[WIDTH-1];
    assign do_up     = SYN_PRE & (SYN_BIST_REF ? ~w_lt_half : V_UP);
    assign do_down   = SYN_PRE & (SYN_BIST_REF ?  w_lt_half : V_DOWN);
    assign overflow  = SYN_PRE & ((do_up && (&WSYN_CURR[WIDTH-1:0])) || (do_down && (~|WSYN_CURR[WIDTH-1:0]))); 

	always @(*) begin
		if      (overflow) WSYN_NEW = WSYN_CURR;
		else if (do_up)    WSYN_NEW = WSYN_CURR + {{(WIDTH){1'b0}},1'b1};
		else if (do_down)  WSYN_NEW = WSYN_CURR - {{(WIDTH){1'b0}},1'b1};
		else               WSYN_NEW = WSYN_CURR;
	end 


endmodule
// Copyright (C) 2016-2019 Université catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "spi_slave.v" - ODIN SPI slave module
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Université catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------


module spi_slave #(
    parameter N = 256,
    parameter M = 8
)(

    // Global inputs -----------------------------------------
    input  wire                 RST_async,

    // SPI slave interface ------------------------------------
    input  wire                 SCK,
    output wire                 MISO,
    input  wire                 MOSI,

    // Control interface for readback -------------------------
    output reg                  CTRL_READBACK_EVENT,
    output reg                  CTRL_PROG_EVENT,
    output reg  [      2*M-1:0] CTRL_SPI_ADDR,
    output reg  [          1:0] CTRL_OP_CODE,
    output reg  [      2*M-1:0] CTRL_PROG_DATA,
    input  wire [         31:0] SYNARRAY_RDATA,
    input  wire [        127:0] NEUR_STATE,

    // Configuration registers output -------------------------
    output reg                  SPI_GATE_ACTIVITY,
    output reg                  SPI_OPEN_LOOP,
    output reg  [        N-1:0] SPI_SYN_SIGN,
    output reg  [         19:0] SPI_BURST_TIMEREF,
    output reg                  SPI_OUT_AER_MONITOR_EN,
    output reg                  SPI_AER_SRC_CTRL_nNEUR,
    output reg  [        M-1:0] SPI_MONITOR_NEUR_ADDR,
    output reg  [        M-1:0] SPI_MONITOR_SYN_ADDR,
    output reg                  SPI_UPDATE_UNMAPPED_SYN,
	output reg                  SPI_PROPAGATE_UNMAPPED_SYN,
	output reg                  SPI_SDSP_ON_SYN_STIM
); 

	//----------------------------------------------------------------------------------
	//	REG & WIRES :
	//----------------------------------------------------------------------------------
    
	reg  [5:0]     spi_cnt;
    
    wire [   31:0] readback_weight;
    wire [  127:0] readback_neuron;
	
	reg  [19:0]    spi_shift_reg_out, spi_shift_reg_in;
    reg  [19:0]    spi_data, spi_addr;
    
    genvar i;
    

	//----------------------------------------------------------------------------------
	//	SPI circuitry
	//----------------------------------------------------------------------------------

	// SPI counter
	always @(negedge SCK, posedge RST_async)
		if      (RST_async)        spi_cnt <= 6'd0;
        else if (spi_cnt == 6'd39) spi_cnt <= 6'd0;
		else                       spi_cnt <= spi_cnt + 6'd1;
        
    always @(negedge SCK, posedge RST_async)
		if      (RST_async)        spi_addr <= 20'd0;
		else if (spi_cnt == 6'd19) spi_addr <= spi_shift_reg_in[19:0];
        else                       spi_addr <= spi_addr;
	
    always @(posedge SCK)
        spi_shift_reg_in <= {spi_shift_reg_in[18:0], MOSI};
        
	
	// SPI shift register
	always @(negedge SCK, posedge RST_async)
        if (RST_async) begin
            spi_shift_reg_out   <= 20'b0;
            CTRL_READBACK_EVENT <= 1'b0;
            CTRL_PROG_EVENT     <= 1'b0;
            CTRL_SPI_ADDR       <= {(2*M){1'b0}};
            CTRL_OP_CODE        <= 2'b0;
            CTRL_PROG_DATA      <= {(2*M){1'b0}};
		end else if (spi_shift_reg_in[19] && (spi_cnt == 6'd19)) begin
            spi_shift_reg_out   <= {spi_shift_reg_out[18:0], 1'b0};
            CTRL_READBACK_EVENT <= (spi_shift_reg_in[2*M+1:2*M] != 2'b0);
            CTRL_PROG_EVENT     <= 1'b0;
            CTRL_SPI_ADDR       <= spi_shift_reg_in[2*M-1:  0];
            CTRL_OP_CODE        <= spi_shift_reg_in[2*M+1:2*M];
            CTRL_PROG_DATA      <= {(2*M){1'b0}};
		end else if (spi_shift_reg_in[18] && (spi_cnt == 6'd19)) begin
            spi_shift_reg_out   <= 20'b0;
            CTRL_READBACK_EVENT <= 1'b0;
            CTRL_PROG_EVENT     <= 1'b0;
            CTRL_SPI_ADDR       <= spi_shift_reg_in[2*M-1:  0];
            CTRL_OP_CODE        <= spi_shift_reg_in[2*M+1:2*M];
            CTRL_PROG_DATA      <= {(2*M){1'b0}};
		end else if (spi_addr[19] && (spi_cnt == 6'd31)) begin
            spi_shift_reg_out   <= (CTRL_OP_CODE == 2'b10) ? {readback_weight[7:0],12'b0} : ((CTRL_OP_CODE == 2'b01) ? {readback_neuron[7:0],12'b0} : {spi_shift_reg_out[18:0], 1'b0}); 
            CTRL_READBACK_EVENT <= 1'b0;
            CTRL_PROG_EVENT     <= 1'b0;
            CTRL_SPI_ADDR       <= CTRL_SPI_ADDR;
            CTRL_OP_CODE        <= CTRL_OP_CODE;
            CTRL_PROG_DATA      <= {(2*M){1'b0}};
		end else if (spi_addr[18] && (spi_cnt == 6'd39)) begin
            spi_shift_reg_out   <= {spi_shift_reg_out[18:0], 1'b0};
            CTRL_READBACK_EVENT <= 1'b0;
            CTRL_PROG_EVENT     <= (CTRL_OP_CODE != 2'b0);
            CTRL_SPI_ADDR       <= CTRL_SPI_ADDR;
            CTRL_OP_CODE        <= CTRL_OP_CODE;
            CTRL_PROG_DATA      <= spi_shift_reg_in[2*M-1:0];
		end else begin
            spi_shift_reg_out   <= {spi_shift_reg_out[18:0], 1'b0};
            CTRL_READBACK_EVENT <= CTRL_READBACK_EVENT;
            CTRL_PROG_EVENT     <= 1'b0;
            CTRL_SPI_ADDR       <= CTRL_SPI_ADDR;
            CTRL_OP_CODE        <= CTRL_OP_CODE;
            CTRL_PROG_DATA      <= CTRL_PROG_DATA;
        end
         
    assign readback_weight = SYNARRAY_RDATA >> (({3'b0,CTRL_SPI_ADDR[2*M-2:2*M-3]} << 3));
    assign readback_neuron =     NEUR_STATE >> (({3'b0,CTRL_SPI_ADDR[2*M-1:  M  ]} << 3));
    
	// SPI MISO
	assign MISO = spi_shift_reg_out[19];

    
	//----------------------------------------------------------------------------------
	//	Output config. registers
	//----------------------------------------------------------------------------------
  
    //SPI_GATE_ACTIVITY - 1 bit - address 0
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd0) && (spi_cnt == 6'd39))    SPI_GATE_ACTIVITY <= MOSI;
        else                                                                                        SPI_GATE_ACTIVITY <= SPI_GATE_ACTIVITY;
        
    //SPI_OPEN_LOOP - 1 bit - address 1
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd1) && (spi_cnt == 6'd39))   SPI_OPEN_LOOP <= MOSI;
        else                                                                                       SPI_OPEN_LOOP <= SPI_OPEN_LOOP;
    
    //SPI_SYN_SIGN - 256 bits - addresses 2 to 17
    generate
        for (i=0; i<(N>>4); i=i+1) begin
            always @(posedge SCK)
                if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == (16'd2+i)) && (spi_cnt == 6'd39)) SPI_SYN_SIGN[16*i+15:16*i] <= {spi_shift_reg_in[14:0], MOSI};
                else                                                                                         SPI_SYN_SIGN[16*i+15:16*i] <= SPI_SYN_SIGN[16*i+15:16*i];
        end
    endgenerate
    
    //SPI_BURST_TIMEREF - 20 bits - address 18
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd18) && (spi_cnt == 6'd39))  SPI_BURST_TIMEREF <= {spi_shift_reg_in[18:0], MOSI};
        else                                                                                       SPI_BURST_TIMEREF <= SPI_BURST_TIMEREF;
    
    //SPI_AER_SRC_CTRL_nNEUR - 1 bit - address 19
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd19) && (spi_cnt == 6'd39))  SPI_AER_SRC_CTRL_nNEUR <= MOSI;
        else                                                                                       SPI_AER_SRC_CTRL_nNEUR <= SPI_AER_SRC_CTRL_nNEUR;
    
    //SPI_OUT_AER_MONITOR_EN - 1 bit - address 20
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd20) && (spi_cnt == 6'd39))  SPI_OUT_AER_MONITOR_EN <= MOSI;
        else                                                                                       SPI_OUT_AER_MONITOR_EN <= SPI_OUT_AER_MONITOR_EN;
    
    //SPI_MONITOR_NEUR_ADDR - M bit - address 21
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd21) && (spi_cnt == 6'd39))  SPI_MONITOR_NEUR_ADDR <= {spi_shift_reg_in[M-2:0], MOSI};
        else                                                                                       SPI_MONITOR_NEUR_ADDR <= SPI_MONITOR_NEUR_ADDR;
    
    //SPI_MONITOR_SYN_ADDR - M bit - address 22
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd22) && (spi_cnt == 6'd39))  SPI_MONITOR_SYN_ADDR <= {spi_shift_reg_in[M-2:0], MOSI};
        else                                                                                       SPI_MONITOR_SYN_ADDR <= SPI_MONITOR_SYN_ADDR;

    //SPI_UPDATE_UNMAPPED_SYN - 1 bit - address 23
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd23) && (spi_cnt == 6'd39))  SPI_UPDATE_UNMAPPED_SYN <= MOSI;
        else                                                                                       SPI_UPDATE_UNMAPPED_SYN <= SPI_UPDATE_UNMAPPED_SYN;
    
	//SPI_PROPAGATE_UNMAPPED_SYN - 1 bit - address 24
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd24) && (spi_cnt == 6'd39))  SPI_PROPAGATE_UNMAPPED_SYN <= MOSI;
        else                                                                                       SPI_PROPAGATE_UNMAPPED_SYN <= SPI_PROPAGATE_UNMAPPED_SYN;
    
	//SPI_SDSP_ON_SYN_STIM - 1 bit - address 25
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd25) && (spi_cnt == 6'd39))  SPI_SDSP_ON_SYN_STIM <= MOSI;
        else                                                                                       SPI_SDSP_ON_SYN_STIM <= SPI_SDSP_ON_SYN_STIM; 
	
    /*                                                 *
     * Some address room for other params if necessary *
     *                                                 */

    
    
endmodule
// Copyright (C) 2016-2019 Université catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "synaptic_core.v" - ODIN synaptic core module
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Université catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------


module synaptic_core #(
    parameter N = 256,
    parameter M = 8
)(
    
    // Global inputs ------------------------------------------
    input  wire           RSTN_syncn,
    input  wire           CLK,
    
    // Inputs from SPI configuration registers ----------------
    input  wire           SPI_GATE_ACTIVITY_sync,
    input  wire [  N-1:0] SPI_SYN_SIGN, 
    input  wire           SPI_UPDATE_UNMAPPED_SYN,
    
    // Inputs from controller ---------------------------------
    input  wire [    7:0] CTRL_PRE_EN,
    input  wire           CTRL_BIST_REF,
    input  wire           CTRL_SYNARRAY_WE,
    input  wire [   12:0] CTRL_SYNARRAY_ADDR,
    input  wire           CTRL_SYNARRAY_CS,
    input  wire [2*M-1:0] CTRL_PROG_DATA,
    input  wire [2*M-1:0] CTRL_SPI_ADDR,
    
    // Inputs from neurons ------------------------------------
    input  wire [  N-1:0] NEUR_V_UP,
    input  wire [  N-1:0] NEUR_V_DOWN,
    
    // Outputs ------------------------------------------------
    output wire [   31:0] SYNARRAY_RDATA,
    output wire [   31:0] SYNARRAY_WDATA,
    output wire           SYN_SIGN
);

    // Internal regs and wires definitions
    
    wire [   31:0] SYNARRAY_WDATA_int;
    wire [  N-1:0] NEUR_V_UP_int, NEUR_V_DOWN_int;
    wire [  N-2:0] syn_sign_dummy;
    
    genvar i;
    
    
    // SDSP update logic

    generate
        for (i=0; i<8; i=i+1) begin
        
            sdsp_update #(
                .WIDTH(3)
            ) sdsp_update_gen (
                // Inputs
                    // General
                .SYN_PRE(CTRL_PRE_EN[i] & (SPI_UPDATE_UNMAPPED_SYN | SYNARRAY_RDATA[(i<<2)+3])),
                .SYN_BIST_REF(CTRL_BIST_REF),
                    // From neuron
                .V_UP(NEUR_V_UP_int[i]),
                .V_DOWN(NEUR_V_DOWN_int[i]),    
                    // From SRAM
                .WSYN_CURR(SYNARRAY_RDATA[(i<<2)+3:(i<<2)]),
                
                // Output
                .WSYN_NEW(SYNARRAY_WDATA_int[(i<<2)+3:(i<<2)])
		    );
        end
    endgenerate

    assign NEUR_V_UP_int   = NEUR_V_UP   >> ({3'b0,CTRL_SYNARRAY_ADDR[4:0]} << 3);
    assign NEUR_V_DOWN_int = NEUR_V_DOWN >> ({3'b0,CTRL_SYNARRAY_ADDR[4:0]} << 3);
    

    // Updated or configured weights to be written to the synaptic memory

    generate
        for (i=0; i<4; i=i+1) begin
            assign SYNARRAY_WDATA[(i<<3)+7:(i<<3)] = SPI_GATE_ACTIVITY_sync
                                                   ?
                                                       ((i == CTRL_SPI_ADDR[14:13])
                                                       ? ((CTRL_PROG_DATA[M-1:0] & ~CTRL_PROG_DATA[2*M-1:M]) | (SYNARRAY_RDATA[(i<<3)+7:(i<<3)] & CTRL_PROG_DATA[2*M-1:M]))
                                                       : SYNARRAY_RDATA[(i<<3)+7:(i<<3)])
                                                   : SYNARRAY_WDATA_int[(i<<3)+7:(i<<3)];
        end
    endgenerate
    
    
    // Synaptic memory wrapper

    SRAM_8192x32_wrapper synarray_0 (
        
        // Global inputs
        .RSTN       (RSTN_syncn),
        .CK         (CLK),
	
		// Control and data inputs
		.CS         (CTRL_SYNARRAY_CS),
		.WE         (CTRL_SYNARRAY_WE),
		.A			(CTRL_SYNARRAY_ADDR),
		.D			(SYNARRAY_WDATA),
		
		// Data output
		.Q			(SYNARRAY_RDATA)
    );
    
    assign {syn_sign_dummy,SYN_SIGN} = SPI_SYN_SIGN >> CTRL_SYNARRAY_ADDR[12:5];


endmodule




module SRAM_8192x32_wrapper (

    // Global inputs
    input         RSTN,                     // Reset
    input         CK,                       // Clock (synchronous read/write)

    // Control and data inputs
    input         CS,                       // Chip select (active low) (init low)
    input         WE,                       // Write enable (active low)
    input  [12:0] A,                        // Address bus 
    input  [31:0] D,                        // Data input bus (write)

    // Data output
    output [31:0] Q                         // Data output bus (read)   
);


    /*
     *  Simple behavioral code for simulation, to be replaced by a 8192-word 32-bit SRAM macro 
     *  or Block RAM (BRAM) memory with the same format for FPGA implementations.
     */      
        reg [31:0] SRAM[8191:0];
        reg [31:0] Qr;
        always @(posedge CK) begin
            Qr <= CS ? SRAM[A] : Qr;
            if (CS & WE) SRAM[A] <= D;
        end
        assign Q = Qr;

    
endmodule
// Copyright (C) 2016-2019 Université catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "izh_calcium.v" - ODIN phenomenological Izhikevich neuron update logic (Calcium part)
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Université catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------

 
module izh_calcium ( 
    input  wire                 param_ca_en,             // calcium concentration enable parameter                                     [SDSP]
    input  wire [          2:0] param_thetamem,          // membrane threshold parameter                                               [SDSP]
    input  wire [          2:0] param_ca_theta1,         // calcium threshold 1 parameter                                              [SDSP]
    input  wire [          2:0] param_ca_theta2,         // calcium threshold 2 parameter                                              [SDSP]
    input  wire [          2:0] param_ca_theta3,         // calcium threshold 3 parameter                                              [SDSP]
    input  wire [          4:0] param_caleak,            // calcium leakage strength parameter                                         [SDSP]
    input  wire                 param_burst_incr,        // effective threshold and calcium incrementation by burst amount parameter  ([SDSP])
    input  wire [          2:0] state_calcium,           // calcium concentration state from SRAM                                      [SDSP]
    input  wire [          4:0] state_caleak_cnt,        // calcium leakage state from SRAM                                            [SDSP]
    input  wire [          3:0] state_core_next,         // next membrane potential state to SRAM
    input  wire [          6:0] event_out,               // neuron spike event output 
    input  wire                 event_tref,              // time reference event signal
    output wire                 v_up_next,               // next SDSP UP condition value                                               [SDSP]
    output wire                 v_down_next,             // next SDSP DOWN condition value                                             [SDSP]
    output reg  [          2:0] state_calcium_next,      // next calcium concentration state to SRAM                                   [SDSP]
    output reg  [          4:0] state_caleak_cnt_next    // next calcium leakage state to SRAM                                         [SDSP]
);


    reg    ca_leak;
    wire   spike_out;

    assign spike_out   = event_out[6];
    assign v_up_next   = param_ca_en && ~state_core_next[3] && (state_core_next[2:0] >= param_thetamem) && (param_ca_theta1 <= state_calcium_next) && (state_calcium_next < param_ca_theta3);
    assign v_down_next = param_ca_en && ~state_core_next[3] && (state_core_next[2:0] <  param_thetamem) && (param_ca_theta1 <= state_calcium_next) && (state_calcium_next < param_ca_theta2);

    always @(*) begin 
        if (param_ca_en) 
            if (spike_out && ~ca_leak && ~&state_calcium)
                state_calcium_next = param_burst_incr ? (((3'b111 - state_calcium) < (event_out[5:3] + {2'b0,~&event_out[5:3]})) ? 3'b111 : (state_calcium + event_out[5:3] + {2'b0,~&event_out[5:3]})) : (state_calcium + 3'b1);
            else if (ca_leak && ~spike_out && |state_calcium)
                state_calcium_next = state_calcium - 3'b1;
            else
                state_calcium_next = state_calcium;
        else
            state_calcium_next = state_calcium;
    end

    always @(*) begin 
        if (param_ca_en && |param_caleak && event_tref)
            if (state_caleak_cnt == (param_caleak - 5'b1)) begin
                state_caleak_cnt_next = 5'b0;
                ca_leak               = 1'b1;
            end else begin
                state_caleak_cnt_next = state_caleak_cnt + 5'b1;
                ca_leak               = 1'b0;
            end
        else begin
            state_caleak_cnt_next = state_caleak_cnt;
            ca_leak               = 1'b0;
        end
    end


endmodule
// Copyright (C) 2016-2019 Université catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "izh_effective_threshold.v" - ODIN phenomenological Izhikevich neuron update logic (effective threshold part)
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Université catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------

 
module izh_effective_threshold ( 
    input  wire [          2:0] param_thr,               // neuron firing threshold parameter
    input  wire                 param_thrvar_en,         // threshold variability and spike frequency adaptation behavior enable parameter
    input  wire                 param_thr_sel_of,        // selection between O (0) and F (1) behaviors parameter (according to Izhikevich behavior numbering)
    input  wire [          3:0] param_thrleak,           // threshold leakage strength parameter
    input  wire                 param_acc_en,            // accommodation behavior enable parameter (requires threshold variability enabled)
    input  wire                 param_burst_incr,        // effective threshold and calcium incrementation by burst amount parameter
    input  wire [          3:0] state_thrmod,            // threshold modificator state from SRAM
    input  wire [          3:0] state_thrleak_cnt,       // threshold leakage state from SRAM
    input  wire [          3:0] state_stim_str_tmp,      // temporary stimulation strength state from SRAM 
    input  wire                 ovfl_inh,                // overflow excitatory type event signal
    input  wire                 ovfl_exc,                // overflow inhibitory type event signal
    input  wire                 event_tref,              // time reference event signal
    input  wire [          6:0] event_out,               // neuron spike event output 
    output reg  [          3:0] state_thrmod_next,       // next threshold modificator state to SRAM
    output reg  [          3:0] state_thrleak_cnt_next,  // next threshold leakage state to SRAM
    output wire [          3:0] threshold_eff            // neuron current effective threshold signal
);


    reg        thr_leak;
    wire [3:0] predicted_acc_thr;
    wire       spike_out;

    assign predicted_acc_thr = param_acc_en ? (state_stim_str_tmp + {1'b0,param_thr}): 4'b0;
    assign spike_out         = event_out[6];

    always @(*) begin 
        if (param_acc_en)
            if (event_tref)
                if (~state_stim_str_tmp[3] && predicted_acc_thr[3])
                    state_thrmod_next = 4'b0111 - {1'b0,param_thr};
                else if (state_stim_str_tmp[3] && predicted_acc_thr[3])
                    state_thrmod_next = 4'b0001 - {1'b0,param_thr};
                else
                    state_thrmod_next = state_stim_str_tmp;
            else 
                state_thrmod_next = state_thrmod;
        else if (param_thrvar_en)
            if (param_thr_sel_of ? spike_out : ovfl_exc)
                state_thrmod_next = param_burst_incr ? (((4'b0111 - threshold_eff) < {1'b0,event_out[5:3]+{2'b0,~&event_out[5:3]}}) ? 4'b0111 : (state_thrmod + {1'b0,event_out[5:3]+{2'b0,~&event_out[5:3]}})) : ((threshold_eff == 4'b0111) ? state_thrmod : (state_thrmod + 4'b1));
            else if (~param_thr_sel_of && ovfl_inh)
                state_thrmod_next = (threshold_eff == 4'b0001) ? state_thrmod : (state_thrmod - 4'b1);
            else if (thr_leak && |state_thrmod)
                state_thrmod_next = state_thrmod[3] ? (state_thrmod + 4'b1) : (state_thrmod - 4'b1);
            else 
                state_thrmod_next = state_thrmod;
        else
            state_thrmod_next = state_thrmod;
    end

    assign threshold_eff = {1'b0,param_thr} + state_thrmod;

    always @(*) begin 
        if (param_thrvar_en && |param_thrleak && event_tref)
            if (state_thrleak_cnt == (param_thrleak - 4'b1)) begin
                state_thrleak_cnt_next = 4'b0;
                thr_leak               = 1'b1;
            end else begin
                state_thrleak_cnt_next = state_thrleak_cnt + 4'b1;
                thr_leak               = 1'b0;
            end
        else begin
            state_thrleak_cnt_next = state_thrleak_cnt;
            thr_leak               = 1'b0;
        end
    end

endmodule
// Copyright (C) 2016-2019 Université catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "izh_input_accumulator.v" - ODIN phenomenological Izhikevich neuron update logic (input accumulator part)
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Université catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------


module izh_input_accumulator #(
	parameter ACC_DEPTH = 11
)( 
    input  wire [          6:0] param_leak_str,   // leakage strength parameter
    input  wire                 param_leak_en,    // leakage enable parameter
    input  wire [          2:0] param_fi_sel,     // accumulator depth parameter for fan-in configuration
    input  wire [ACC_DEPTH-1:0] state_inacc,      // input accumulator state from SRAM
    input  wire [          2:0] syn_weight,       // synaptic weight
    input  wire                 event_leak,       // leakage event trigger
    input  wire                 event_exc,        // excitatory event trigger
    input  wire                 event_inh,        // inhibitory event trigger
    input  wire                 state_refrac,     // neuron in refractory period
    output reg  [ACC_DEPTH-1:0] state_inacc_next, // next input accumulator state to SRAM
    output wire                 ovfl_leak,        // negative leakage overflow signal
    output wire                 ovfl_exc,         // positive excitatory overflow signal
    output wire                 ovfl_inh          // negative inhibitory overflow signal
);


    reg  state_inacc_fi, state_inacc_next_fi;
    wire toggle;


    always @(*) begin 
        if (event_leak)
            state_inacc_next = param_leak_en ? (state_inacc - {{(ACC_DEPTH-7){1'b0}},param_leak_str}) : state_inacc;
        else if (event_exc)
            state_inacc_next = state_inacc + {{(ACC_DEPTH-3){1'b0}},syn_weight};
        else if (event_inh)
            state_inacc_next = state_inacc - {{(ACC_DEPTH-3){1'b0}},syn_weight};
    	else
    		state_inacc_next = state_inacc;
    end

    always @(*)
        case (param_fi_sel) 
            3'd0    : begin state_inacc_fi = state_inacc[3 ]; state_inacc_next_fi = state_inacc_next[3 ]; end
            3'd1    : begin state_inacc_fi = state_inacc[4 ]; state_inacc_next_fi = state_inacc_next[4 ]; end
            3'd2    : begin state_inacc_fi = state_inacc[5 ]; state_inacc_next_fi = state_inacc_next[5 ]; end 
            3'd3    : begin state_inacc_fi = state_inacc[6 ]; state_inacc_next_fi = state_inacc_next[6 ]; end
            3'd4    : begin state_inacc_fi = state_inacc[7 ]; state_inacc_next_fi = state_inacc_next[7 ]; end
            3'd5    : begin state_inacc_fi = state_inacc[8 ]; state_inacc_next_fi = state_inacc_next[8 ]; end 
            3'd6    : begin state_inacc_fi = state_inacc[9 ]; state_inacc_next_fi = state_inacc_next[9 ]; end 
            3'd7    : begin state_inacc_fi = state_inacc[10]; state_inacc_next_fi = state_inacc_next[10]; end
            default : begin state_inacc_fi = state_inacc[3 ]; state_inacc_next_fi = state_inacc_next[3 ]; end
        endcase 

    assign toggle = state_inacc_fi ^ state_inacc_next_fi;
        
    assign ovfl_leak = toggle & event_leak;
    assign ovfl_exc  = toggle & event_exc ;
    assign ovfl_inh  = toggle & event_inh ;


endmodule 
// Copyright (C) 2016-2019 Université catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "izh_neuron state.v" - ODIN phenomenological Izhikevich neuron update logic (neuron state part)
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Université catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------


`define RES_POS          2'd0
`define RES_NEG          2'd1
`define RES_ZERO_TO_P    2'd2
`define RES_ZERO_TO_N    2'd3
 
module izh_neuron_state (
    input  wire [          2:0] param_spk_ref,          // number of spikes per burst parameter
    input  wire [          2:0] param_isi_ref,          // inter-spike-interval in burst parameter
    input  wire [          2:0] param_rfr,              // neuron refractory period parameter
    input  wire [          2:0] param_dapdel,           // delay for spike latency or DAP parameter
    input  wire                 param_spklat_en,        // spike latency enable parameter
    input  wire                 param_dap_en,           // DAP enable parameter
    input  wire                 param_phasic_en,        // phasic behavior enable parameter
    input  wire                 param_mixed_en,         // mixed mode behavior enable parameter
    input  wire                 param_class2_en,        // class 2 excitability enable parameter
    input  wire                 param_neg_en,           // negative state enable parameter
    input  wire                 param_rebound_en,       // rebound behavior enable parameter
    input  wire                 param_inhin_en,         // inhibition-induced behavior enable parameter
    input  wire                 param_bist_en,          // bistability behavior enable parameter
    input  wire                 param_reson_en,         // resonant behavior enable parameter
    input  wire                 param_acc_en,           // accommodation behavior enable parameter (requires threshold variability enabled)
    input  wire                 param_reson_sharp_en,   // sharp resonant behavior enable parameter
    input  wire [          2:0] param_reson_sharp_amt,  // sharp resonant behavior time constant parameter
    input  wire                 state_refrac,           // refractory period state from SRAM 
    input  wire [          3:0] state_core,             // membrane potential state from SRAM 
    input  wire [          2:0] state_dapdel_cnt,       // dapdel counter state from SRAM  
    input  wire                 state_phasic_lock,      // phasic lock state from SRAM
    input  wire                 state_mixed_lock,       // mixed lock state from SRAM
    input  wire                 state_spkout_done,      // spike sent in current Tref interval state from SRAM
    input  wire                 state_bist_lock,        // bistability lock state from SRAM
    input  wire                 state_inhin_lock,       // inhibition-induced lock state from SRAM
    input  wire [          1:0] state_reson_sign,       // resonant sign state from SRAM
    input  wire                 state_burst_lock,       // burst lock state from SRAM
    input  wire [          3:0] state_stim_str_tmp,     // temporary stimulation strength state from SRAM 
    input  wire                 ovfl_leak,              // overflow leakage type event
    input  wire                 ovfl_inh,               // overflow excitatory type event
    input  wire                 ovfl_exc,               // overflow inhibitory type event
    input  wire                 event_tref,             // time reference event
    input  wire                 burst_end,              // end of burst signal
    input  wire                 stim_gt_thr_exc,        // excitatory stimulation strength greater than threshold signal
    input  wire                 stim_tmp_gt_thr_exc,    // current excitatory stimulation strength greater than threshold signal
    input  wire                 stim_gt_thr_inh,        // inhibitory stimulation strength greater than threshold signal
    input  wire                 stim_tmp_gt_thr_inh,    // current inhibitory stimulation strength greater than threshold signal
    input  wire                 stim_lone_spike_exc,    // isolated excitatory spike signal
    input  wire                 stim_lone_spike_inh,    // isolated inhibitory spike signal
    input  wire                 stim_zero,              // zero stimulation signal
    input  wire [          3:0] threshold_eff,          // neuron current effective threshold signal
    output wire                 state_refrac_next,      // next refractory period state to SRAM
    output wire [          3:0] state_core_next,        // next membrane potential state to SRAM 
    output reg  [          2:0] state_dapdel_cnt_next,  // next dapdel counter state to SRAM
    output reg                  state_phasic_lock_next, // next phasic lock state to SRAM
    output reg                  state_mixed_lock_next,  // next mixed lock state to SRAM
    output reg                  state_spkout_done_next, // next spike sent in current Tref interval state to SRAM
    output reg                  state_bist_lock_next,   // next bistability lock state to SRAM
    output reg                  state_inhin_lock_next,  // next inhibition-induced lock state to SRAM
    output wire [          1:0] state_reson_sign_next,  // next resonant sign state to SRAM
    output reg                  state_burst_lock_next,  // next burst lock state to SRAM
    output wire [          6:0] event_out               // neuron spike event output   
);


    reg [3:0] state_core_next_i;
    reg [1:0] state_reson_sign_next_i;

    reg    spike_out;
    wire   refrac_en;
    wire   dap_event, spklat_event;

    assign event_out             = state_mixed_lock ? {spike_out, 3'b000, 3'b0} : {spike_out, param_spk_ref, param_isi_ref};
    assign refrac_en             = ~param_dap_en & |param_rfr;

    always @(*) begin 
        if (param_spklat_en && |state_dapdel_cnt)
            state_core_next_i = state_core;
        else if (state_phasic_lock && ~|state_core)
            state_core_next_i = state_core;
        else
            if (event_tref)
                if      (param_reson_en)
                    state_core_next_i = (state_reson_sign == `RES_ZERO_TO_N) ? (state_core - 4'b1) : state_core;
                else if (state_refrac)
                    state_core_next_i = state_burst_lock ? state_core : (state_core + 4'b1);
                else if (param_acc_en)
                    state_core_next_i = state_spkout_done ? state_core : (state_core - state_stim_str_tmp);
                else if (param_dap_en && (state_dapdel_cnt == 3'b1) && (state_core > 4'b0))
                    state_core_next_i = 4'b0;
                else if (ovfl_leak && |state_core)
                    state_core_next_i = state_core[3] ? (state_core + 4'b1) : (state_core - 4'b1);
                else
                    state_core_next_i = state_core;
            else if (ovfl_inh)
                if (param_reson_en)
                    state_core_next_i = (((state_reson_sign == `RES_ZERO_TO_N) || (state_reson_sign == `RES_NEG)) && ~(state_core == 4'b0111)) ? (state_core + 4'b1) : ((((state_reson_sign == `RES_ZERO_TO_P) || (state_reson_sign == `RES_POS)) && ~(state_core == 4'b0)) ? (state_core - 4'b1) : state_core);
                else
                    state_core_next_i = state_refrac ? state_core : ((param_neg_en ? (state_core == 4'b1000) : ~|state_core) ? state_core : (state_core - 1'b1)); 
            else if (ovfl_exc)
                if (param_reson_en)
                    state_core_next_i = (((state_reson_sign == `RES_ZERO_TO_N) || (state_reson_sign == `RES_NEG)) && ~(state_core == 4'b0)) ? (state_core - 4'b1) : ((((state_reson_sign == `RES_ZERO_TO_P) || (state_reson_sign == `RES_POS)) && ~(state_core == 4'b0111)) ? (state_core + 4'b1) : state_core);
                else
                    state_core_next_i = state_refrac ? state_core : ((param_class2_en && ~stim_gt_thr_exc && ~stim_tmp_gt_thr_exc) ? state_core: ((state_core == 4'b0111) ? state_core : (state_core + 1'b1)));
            else 
                state_core_next_i = state_core;
    end

    assign spklat_event      =  param_spklat_en & (state_core_next_i == threshold_eff) & (state_core != threshold_eff);
    assign dap_event         =  param_dap_en & spike_out;
    assign state_refrac_next = (spike_out || state_inhin_lock_next) ? (refrac_en && ~param_reson_en) : ((state_core_next_i == 4'b0) ? 1'b0 : state_refrac);

    always @(*) begin 
        if (~param_reson_en)
            state_reson_sign_next_i = `RES_POS;
        else
            if (event_tref)
                if (~|state_core)
                    state_reson_sign_next_i = `RES_POS;
                else begin
                    case(state_reson_sign) 
                        `RES_POS      : state_reson_sign_next_i = `RES_ZERO_TO_N;
                        `RES_NEG      : state_reson_sign_next_i = `RES_ZERO_TO_P;
                        `RES_ZERO_TO_P: state_reson_sign_next_i = `RES_POS;
                        `RES_ZERO_TO_N: if (state_core_next_i == 4'b0)
                                            state_reson_sign_next_i = `RES_POS;
                                        else
                                            state_reson_sign_next_i = `RES_NEG;
                        default:        state_reson_sign_next_i = state_reson_sign;
                    endcase
                end
            else
                state_reson_sign_next_i = state_reson_sign;
    end

    always @(*) begin 
        if (param_reson_sharp_en)
            if (event_tref && ~&state_dapdel_cnt)
                state_dapdel_cnt_next = state_dapdel_cnt + 3'b1;
            else if (ovfl_exc)
                state_dapdel_cnt_next = 3'b0;
            else 
                state_dapdel_cnt_next = state_dapdel_cnt;
        else
            if (dap_event || spklat_event)
                state_dapdel_cnt_next = param_dapdel;
            else
                if (event_tref && |state_dapdel_cnt)
                    state_dapdel_cnt_next = state_dapdel_cnt - 3'b1;
                else 
                    state_dapdel_cnt_next = state_dapdel_cnt;
    end

    always @(*) begin 
        if (spike_out && (stim_tmp_gt_thr_exc || stim_gt_thr_exc)) begin
            state_phasic_lock_next = param_phasic_en;
            state_mixed_lock_next  = param_mixed_en;
        end else if (event_tref && state_spkout_done && (~|state_core || state_refrac) && stim_tmp_gt_thr_exc) begin
            state_phasic_lock_next = param_phasic_en;
            state_mixed_lock_next  = param_mixed_en;
        end else if (~stim_gt_thr_exc) begin
            state_phasic_lock_next = 1'b0;
            state_mixed_lock_next  = 1'b0;
        end else begin
            state_phasic_lock_next = state_phasic_lock;
            state_mixed_lock_next  = state_mixed_lock;
        end
    end

    always @(*) begin 
        if (event_tref)
            state_spkout_done_next = 1'b0;
        else if (spike_out)
            state_spkout_done_next = 1'b1;
        else
            state_spkout_done_next = state_spkout_done;
    end

    always @(*) begin 
        if (event_tref && param_bist_en)
            state_bist_lock_next = stim_lone_spike_exc ? ~state_bist_lock : state_bist_lock;
        else
            state_bist_lock_next = state_bist_lock;
    end

    always @(*) begin 
        if (param_inhin_en && ~state_refrac && ((-state_core) == threshold_eff))
            state_inhin_lock_next = 1'b1;
        else if (event_tref && state_inhin_lock && (stim_zero))
            state_inhin_lock_next = 1'b0;
        else
            state_inhin_lock_next = state_inhin_lock;
    end

    always @(*) begin 
        if (param_reson_sharp_en)
            spike_out = (ovfl_exc && (state_dapdel_cnt == param_reson_sharp_amt));
        else if (param_spklat_en)
            spike_out = (event_tref && (state_dapdel_cnt == 3'b1));
        else if (param_rebound_en)
            spike_out = stim_lone_spike_inh || (state_core_next_i == threshold_eff);
        else if (param_bist_en)
            spike_out = (~state_bist_lock && stim_lone_spike_exc) || (state_bist_lock && ~|state_core_next_i) || (state_core_next_i == threshold_eff);
        else if (state_inhin_lock)
            spike_out = (state_core_next_i == 4'b0);
        else if (param_reson_en)
            spike_out = (state_reson_sign_next_i == `RES_POS) && (state_core_next_i == threshold_eff);
        else
            spike_out = (state_core_next_i == threshold_eff);
    end

    always @(*) begin 
        if (event_out[6] && |event_out[5:3])
            state_burst_lock_next = 1'b1;
        else if (burst_end)
            state_burst_lock_next = 1'b0;
        else
            state_burst_lock_next = state_burst_lock;
    end

    assign state_reson_sign_next = (spike_out && param_reson_en) ?                                                                  `RES_NEG : state_reson_sign_next_i;
    assign state_core_next       =  spike_out                    ? ((param_dap_en || param_reson_en) ? {1'b0,param_rfr} : -{1'b0,param_rfr}) : state_core_next_i;


endmodule 
// Copyright (C) 2016-2019 Université catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "izh_stimulation_strength.v" - ODIN phenomenological Izhikevich neuron update logic (stimulation strength part)
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Université catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------


module izh_stimulation_strength ( 
    input  wire [          2:0] param_stim_thr,          // stimulation threshold (phasic, mixed,...) parameter
    input  wire [          3:0] state_stim_str,          // stimulation strength state from SRAM 
    input  wire [          3:0] state_stim_str_tmp,      // temporary stimulation strength state from SRAM 
    input  wire [          1:0] state_stim0_prev,        // zero stimulation monitoring state from SRAM
    input  wire [          1:0] state_inhexc_prev,       // inh/exc stimulation monitoring state from SRAM
    input  wire                 ovfl_inh,                // overflow excitatory type event signal
    input  wire                 ovfl_exc,                // overflow inhibitory type event signal
    input  wire                 event_tref,              // time reference event signal
    output reg  [          3:0] state_stim_str_next,     // next stimulation strength state to SRAM 
    output reg  [          3:0] state_stim_str_tmp_next, // next temporary stimulation strength state to SRAM 
    output reg  [          1:0] state_stim0_prev_next,   // next zero stimulation monitoring state to SRAM
    output reg  [          1:0] state_inhexc_prev_next,  // next inh/exc stimulation monitoring state to SRAM
    output wire                 stim_gt_thr_exc,         // excitatory stimulation strength greater than threshold signal
    output wire                 stim_tmp_gt_thr_exc,     // current excitatory stimulation strength greater than threshold signal
    output wire                 stim_gt_thr_inh,         // inhibitory stimulation strength greater than threshold signal
    output wire                 stim_tmp_gt_thr_inh,     // current inhibitory stimulation strength greater than threshold signal
    output wire                 stim_lone_spike_exc,     // isolated excitatory spike signal
    output wire                 stim_lone_spike_inh,     // isolated inhibitory spike signal
    output wire                 stim_zero                // zero stimulation signal
);


    assign stim_gt_thr_exc     = ~state_stim_str[3]     && (      state_stim_str[2:0]  >=       param_stim_thr );
    assign stim_tmp_gt_thr_exc = ~state_stim_str_tmp[3] && (  state_stim_str_tmp[2:0]  >=       param_stim_thr );
    assign stim_gt_thr_inh     =  state_stim_str[3]     && ((    -state_stim_str     ) >= {1'b0,param_stim_thr});
    assign stim_tmp_gt_thr_inh =  state_stim_str_tmp[3] && ((-state_stim_str_tmp     ) >= {1'b0,param_stim_thr});
    assign stim_lone_spike_exc =  event_tref && (state_stim_str_tmp == 4'b0) && ~state_stim0_prev[1] && state_inhexc_prev[0];
    assign stim_lone_spike_inh =  event_tref && (state_stim_str_tmp == 4'b0) && ~state_stim0_prev[1] && state_inhexc_prev[1];
    assign stim_zero           =  event_tref && (state_stim_str_tmp == 4'b0);

    always @(*) begin 
        if (event_tref)
            state_stim_str_tmp_next = 4'b0;
        else if (ovfl_exc && (state_stim_str_tmp != 4'b0111))
            state_stim_str_tmp_next = state_stim_str_tmp + 4'b1;
        else if (ovfl_inh && (state_stim_str_tmp != 4'b1001))
            state_stim_str_tmp_next = state_stim_str_tmp - 4'b1;
        else
            state_stim_str_tmp_next = state_stim_str_tmp;
    end

    always @(*) begin 
        if (event_tref)
            state_stim_str_next = state_stim_str_tmp;
        else
            state_stim_str_next = state_stim_str;
    end

    always @(*) begin 
        if (event_tref)
            state_stim0_prev_next = {state_stim0_prev[0], ~(state_stim_str_tmp == 4'b0)};
        else
            state_stim0_prev_next = state_stim0_prev;
    end

    always @(*) begin 
        if (event_tref)
            state_inhexc_prev_next = {stim_tmp_gt_thr_inh, stim_tmp_gt_thr_exc};
        else
            state_inhexc_prev_next = state_inhexc_prev;
    end
    
    
endmodule 
// Copyright (C) 2016-2019 Université catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "lif_calcium.v" - ODIN leaky integrate-and-fire (LIF) neuron update logic (Calcium part)
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Université catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------


module lif_calcium ( 
    input  wire                 param_ca_en,             // calcium concentration enable parameter
    input  wire [          7:0] param_thetamem,          // membrane threshold parameter              [SDSP]
    input  wire [          2:0] param_ca_theta1,         // calcium threshold 1parameter              [SDSP]
    input  wire [          2:0] param_ca_theta2,         // calcium threshold 2 parameter             [SDSP]
    input  wire [          2:0] param_ca_theta3,         // calcium threshold 3 parameter             [SDSP]
    input  wire [          4:0] param_caleak,            // calcium leakage strength parameter        [SDSP]
    input  wire [          2:0] state_calcium,           // calcium concentration state from SRAM     [SDSP]
    input  wire [          4:0] state_caleak_cnt,        // calcium leakage state from SRAM           [SDSP]
    input  wire [          7:0] state_core_next,         // next membrane potential state to SRAM 
    input  wire                 spike_out,               // neuron spike event signal
    input  wire                 event_tref,              // time reference event signal
    output wire                 v_up_next,               // next SDSP UP condition value signal       [SDSP]
    output wire                 v_down_next,             // next SDSP DOWN condition value signal     [SDSP]
    output reg  [          2:0] state_calcium_next,      // next calcium concentration state to SRAM  [SDSP]
    output reg  [          4:0] state_caleak_cnt_next    // next calcium leakage state to SRAM        [SDSP]
);


    reg    ca_leak;

    assign v_up_next   = param_ca_en && (state_core_next >= param_thetamem) && (param_ca_theta1 <= state_calcium_next) && (state_calcium_next < param_ca_theta3);
    assign v_down_next = param_ca_en && (state_core_next <  param_thetamem) && (param_ca_theta1 <= state_calcium_next) && (state_calcium_next < param_ca_theta2);

    always @(*) begin 

        if (param_ca_en)
            if (spike_out && ~ca_leak && ~&state_calcium)
                state_calcium_next = state_calcium + 3'b1;
            else if (ca_leak && ~spike_out && |state_calcium)
                state_calcium_next = state_calcium - 3'b1;
            else
                state_calcium_next = state_calcium;
        else
            state_calcium_next = state_calcium;
    end

    always @(*) begin 

        if (param_ca_en && |param_caleak && event_tref)
            if (state_caleak_cnt == (param_caleak - 5'b1)) begin
                state_caleak_cnt_next = 5'b0;
                ca_leak               = 1'b1;
            end else begin
                state_caleak_cnt_next = state_caleak_cnt + 5'b1;
                ca_leak               = 1'b0;
            end
        else begin
            state_caleak_cnt_next = state_caleak_cnt;
            ca_leak               = 1'b0;
        end
    end

endmodule
// Copyright (C) 2016-2019 Université catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "lif_neuron_state.v" - ODIN leaky integrate-and-fire (LIF) neuron update logic (neuron state part)
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Université catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------


module lif_neuron_state ( 
    input  wire [          6:0] param_leak_str,         // leakage strength parameter
    input  wire                 param_leak_en,          // leakage enable parameter
    input  wire [          7:0] param_thr,              // neuron firing threshold parameter
    input  wire [          7:0] state_core,             // membrane potential state from SRAM 
    input  wire                 event_leak,             // leakage type event
    input  wire                 event_inh,              // excitatory type event
    input  wire                 event_exc,              // inhibitory type event
    input  wire [          2:0] syn_weight,             // synaptic weight
    output wire [          7:0] state_core_next,        // next membrane potential state to SRAM 
    output wire [          6:0] event_out               // neuron spike event output  
);


    reg  [7:0] state_core_next_i;
    wire [7:0] state_leak, state_inh, state_exc;
    wire       spike_out;

    assign spike_out       = (state_core_next_i >= param_thr);
    assign event_out       = {spike_out, 3'b000, 3'b0};
    assign state_core_next =  spike_out ? 8'd0 : state_core_next_i;

    always @(*) begin 

            if (event_leak && param_leak_en)
                if (state_core >= state_leak)
                    state_core_next_i = state_leak;
                else
                    state_core_next_i = 8'b0;
            else if (event_inh)
                if (state_core >= state_inh)
                    state_core_next_i = state_inh;
                else
                    state_core_next_i = 8'b0;
            else if (event_exc)
                if (state_core <= state_exc)
                    state_core_next_i = state_exc;
                else
                    state_core_next_i = 8'hFF;
            else 
                state_core_next_i = state_core;
    end

    assign state_leak = (state_core - {1'b0,param_leak_str});
    assign state_inh  = (state_core - {5'b0,syn_weight});
    assign state_exc  = (state_core + {5'b0,syn_weight});

endmodule 
