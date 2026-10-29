--------------------------------------------------------------------------------
-- baud_gen.vhd
-- Clock divider for the UART (baud rate generator).
--
-- UART has no separate clock line, so both the transmitter and the receiver
-- must measure the bit time themselves. This module divides the system clock
-- and produces a one-clock-wide pulse "tick" 16 times per bit (16x
-- oversampling). 16 ticks = one bit on the line.
--
-- Example: CLK_FREQ_HZ = 50 MHz, BAUD_RATE = 115200
--   DIVISOR = 50_000_000 / (115200 * 16) = 27
--   real baud rate = 50_000_000 / (27 * 16) = 115740 baud (error +0.47 %)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity baud_gen is
    generic (
        CLK_FREQ_HZ : positive := 50_000_000;  -- system clock frequency, Hz
        BAUD_RATE   : positive := 115_200      -- required baud rate, bit/s
    );
    port (
        clk  : in  std_logic;   -- system clock
        rst  : in  std_logic;   -- synchronous reset, active high
        tick : out std_logic    -- '1' for one clk period, 16 times per bit
    );
end entity baud_gen;

architecture rtl of baud_gen is

    -- how many clk periods fit into one tick period
    constant DIVISOR : positive := CLK_FREQ_HZ / (BAUD_RATE * 16);

    -- counter of clk periods inside one tick period
    signal cnt : integer range 0 to DIVISOR - 1 := 0;

begin

    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cnt  <= 0;
                tick <= '0';
            elsif cnt = DIVISOR - 1 then
                cnt  <= 0;          -- start a new tick period
                tick <= '1';        -- pulse for exactly one clk period
            else
                cnt  <= cnt + 1;
                tick <= '0';
            end if;
        end if;
    end process;

end architecture rtl;
