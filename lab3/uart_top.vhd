--------------------------------------------------------------------------------
-- uart_top.vhd
-- Top level of the UART module: clock divider + transmitter + receiver.
-- This entity is used both in the testbench and for synthesis.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity uart_top is
    generic (
        CLK_FREQ_HZ : positive := 50_000_000;  -- system clock frequency, Hz
        BAUD_RATE   : positive := 115_200      -- baud rate, bit/s
    );
    port (
        clk      : in  std_logic;                     -- system clock
        rst      : in  std_logic;                     -- synchronous reset, active high
        -- transmitter side
        tx_start : in  std_logic;                     -- '1' for one clk: send tx_data
        tx_data  : in  std_logic_vector(7 downto 0);  -- byte to send
        txd      : out std_logic;                     -- serial output line
        tx_busy  : out std_logic;                     -- transmitter is busy
        tx_done  : out std_logic;                     -- frame has been sent
        -- receiver side
        rxd      : in  std_logic;                     -- serial input line
        rx_data  : out std_logic_vector(7 downto 0);  -- received byte
        rx_valid : out std_logic;                     -- rx_data is valid
        rx_error : out std_logic                      -- framing error (bad stop bit)
    );
end entity uart_top;

architecture rtl of uart_top is

    signal tick : std_logic;   -- 16x baud pulse shared by Tx and Rx

begin

    -- clock divider: system clock -> 16 pulses per bit
    u_baud_gen : entity work.baud_gen
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ,
            BAUD_RATE   => BAUD_RATE
        )
        port map (
            clk  => clk,
            rst  => rst,
            tick => tick
        );

    -- transmitter
    u_tx : entity work.uart_tx
        port map (
            clk      => clk,
            rst      => rst,
            tick     => tick,
            tx_start => tx_start,
            tx_data  => tx_data,
            txd      => txd,
            tx_busy  => tx_busy,
            tx_done  => tx_done
        );

    -- receiver
    u_rx : entity work.uart_rx
        port map (
            clk      => clk,
            rst      => rst,
            tick     => tick,
            rxd      => rxd,
            rx_data  => rx_data,
            rx_valid => rx_valid,
            rx_error => rx_error
        );

end architecture rtl;
