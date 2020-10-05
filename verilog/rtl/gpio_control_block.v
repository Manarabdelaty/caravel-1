/* 
 *---------------------------------------------------------------------
 * See gpio_control_block for description.  This module is like
 * gpio_contro_block except that it has an additional two management-
 * Soc-facing pins, which are the out_enb line and the output line.
 * If the chip is configured for output with the oeb control
 * register = 1, then the oeb line is controlled by the additional
 * signal from the management SoC.  If the oeb control register = 0,
 * then the output is disabled completely.  The "io" line is input
 * only in this module.
 *
 *---------------------------------------------------------------------
 */

/*
 *---------------------------------------------------------------------
 *
 * This module instantiates a shift register chain that passes through
 * each gpio cell.  These are connected end-to-end around the padframe
 * periphery.  The purpose is to avoid a massive number of control
 * wires between the digital core and I/O, passing through the user area.
 *
 * See mprj_ctrl.v for the module that registers the data for each
 * I/O and drives the input to the shift register.
 *
 *---------------------------------------------------------------------
 */

module gpio_control_block #(
    parameter PAD_CTRL_BITS = 13,
    // Parameterized initial startup state of the pad.
    // The default parameters if unspecified is for the pad to be
    // an input with no pull-up or pull-down, so that it is disconnected
    // from the outside world.
    parameter HOLD_INIT = 1'b0,
    parameter SLOW_INIT = 1'b0,
    parameter TRIP_INIT = 1'b0,
    parameter IB_INIT = 1'b0,
    parameter IENB_INIT = 1'b0,
    parameter OENB_INIT = 1'b1,
    parameter DM_INIT = 3'b001,
    parameter AENA_INIT = 1'b0,
    parameter ASEL_INIT = 1'b0,
    parameter APOL_INIT = 1'b0
) (
    // Management Soc-facing signals
    input  	 resetn,		// Global reset
    input  	 serial_clock,

    output       mgmt_gpio_in,		// Management from pad (input only)
    input        mgmt_gpio_out,		// Management to pad (output only)
    input        mgmt_gpio_oeb,		// Management to pad (output only)

    // Serial data chain for pad configuration
    input  	 serial_data_in,
    output 	 serial_data_out,

    // User-facing signals
    input        user_gpio_out,		// User space to pad
    input        user_gpio_oeb,		// Output enable (user)
    output	 user_gpio_in,		// Pad to user space

    // Pad-facing signals (Pad GPIOv2)
    output	 pad_gpio_holdover,
    output	 pad_gpio_slow_sel,
    output	 pad_gpio_vtrip_sel,
    output       pad_gpio_inenb,
    output       pad_gpio_ib_mode_sel,
    output	 pad_gpio_ana_en,
    output	 pad_gpio_ana_sel,
    output	 pad_gpio_ana_pol,
    output [2:0] pad_gpio_dm,
    output       pad_gpio_outenb,
    output	 pad_gpio_out,
    input	 pad_gpio_in
);

    /* Parameters defining the bit offset of each function in the chain */
    localparam MGMT_EN = 0;
    localparam OEB = 1;
    localparam HLDH = 2;
    localparam INP_DIS = 3;
    localparam MOD_SEL = 4;
    localparam AN_EN = 5;
    localparam AN_SEL = 6;
    localparam AN_POL = 7;
    localparam SLOW = 8;
    localparam TRIP = 9;
    localparam DM = 10;

    /* Internally registered signals */
    reg	 	mgmt_ena;		// Enable management SoC to access pad
    reg	 	gpio_holdover;
    reg	 	gpio_slow_sel;
    reg	  	gpio_vtrip_sel;
    reg  	gpio_inenb;
    reg	 	gpio_ib_mode_sel;
    reg  	gpio_outenb;
    reg [2:0] 	gpio_dm;
    reg	 	gpio_ana_en;
    reg	 	gpio_ana_sel;
    reg	 	gpio_ana_pol;

    /* Derived output values */
    wire	pad_gpio_holdover;
    wire	pad_gpio_slow_sel;
    wire	pad_gpio_vtrip_sel;
    wire      	pad_gpio_inenb;
    wire       	pad_gpio_ib_mode_sel;
    wire	pad_gpio_ana_en;
    wire	pad_gpio_ana_sel;
    wire	pad_gpio_ana_pol;
    wire [2:0]  pad_gpio_dm;
    wire        pad_gpio_outenb;
    wire	pad_gpio_out;
    wire	pad_gpio_in;

    /* Serial shift for the above (latched) values */
    reg [PAD_CTRL_BITS-1:0] shift_register;

    /* Utilize reset and clock to encode a load operation */
    wire load_data;
    wire int_reset;

    /* Create internal reset and load signals from input reset and clock */
    assign serial_data_out = shift_register[PAD_CTRL_BITS-1]; 
    assign int_reset = (~resetn) & (~serial_clock);
    assign load_data = (~resetn) & serial_clock;

    always @(posedge serial_clock or posedge int_reset) begin
	if (int_reset == 1'b1) begin
	    /* Clear shift register */
	    shift_register <= 'd0;
	end else begin
	    /* Shift data in */
	    shift_register <= {shift_register[PAD_CTRL_BITS-2:0], serial_data_in};
	end
    end

    always @(posedge load_data or posedge int_reset) begin
	if (int_reset == 1'b1) begin
	    /* Initial state on reset:  Pad set to management input */
	    mgmt_ena <= 1'b1;		// Management SoC has control over all I/O
	    gpio_holdover <= HOLD_INIT;	 // All signals latched in hold mode
	    gpio_slow_sel <= SLOW_INIT;	 // Fast slew rate
	    gpio_vtrip_sel <= TRIP_INIT; // CMOS mode
            gpio_ib_mode_sel <= IB_INIT; // CMOS mode
	    gpio_inenb <= IENB_INIT;	 // Input enabled
	    gpio_outenb <= OENB_INIT;	 // (unused placeholder)
	    gpio_dm <= DM_INIT;		 // Configured as input only
	    gpio_ana_en <= AENA_INIT;	 // Digital enabled
	    gpio_ana_sel <= ASEL_INIT;	 // Don't-care when gpio_ana_en = 0
	    gpio_ana_pol <= APOL_INIT;	 // Don't-care when gpio_ana_en = 0
	end else begin
	    /* Load data */
	    mgmt_ena 	     <= shift_register[MGMT_EN];
	    gpio_outenb      <= shift_register[OEB];
	    gpio_holdover    <= shift_register[HLDH]; 
	    gpio_inenb 	     <= shift_register[INP_DIS];
	    gpio_ib_mode_sel <= shift_register[MOD_SEL];
	    gpio_ana_en      <= shift_register[AN_EN];
	    gpio_ana_sel     <= shift_register[AN_SEL];
	    gpio_ana_pol     <= shift_register[AN_POL];
	    gpio_slow_sel    <= shift_register[SLOW];
	    gpio_vtrip_sel   <= shift_register[TRIP];
	    gpio_dm 	     <= shift_register[DM+2:DM];

	end
    end

    /* These pad configuration signals are static and do not change	*/
    /* after setup.							*/

    assign pad_gpio_holdover 	= gpio_holdover;
    assign pad_gpio_slow_sel 	= gpio_slow_sel;
    assign pad_gpio_vtrip_sel	= gpio_vtrip_sel;
    assign pad_gpio_ib_mode_sel	= gpio_ib_mode_sel;
    assign pad_gpio_ana_en	= gpio_ana_en;
    assign pad_gpio_ana_sel	= gpio_ana_sel;
    assign pad_gpio_ana_pol	= gpio_ana_pol;
    assign pad_gpio_dm		= gpio_dm;
    assign pad_gpio_inenb 	= gpio_inenb;

    /* Implement pad control behavior depending on state of mgmt_ena */

    assign pad_gpio_out    =  (mgmt_ena) ? mgmt_gpio_out : user_gpio_out; 
    assign pad_gpio_outenb =  (mgmt_ena) ? mgmt_gpio_oeb : user_gpio_oeb;

    assign user_gpio_in =    (mgmt_ena) ? 1'b0 : pad_gpio_in;
    assign mgmt_gpio_in =    (mgmt_ena) ? pad_gpio_in : 1'b0;

endmodule