# Clock constraint for uart_top: 50 MHz system clock (period 20 ns)
create_clock -name clk -period 20.000 [get_ports {clk}]
derive_clock_uncertainty
