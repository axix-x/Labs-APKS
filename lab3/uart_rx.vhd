--------------------------------------------------------------------------------
-- uart_rx.vhd
-- UART receiver (Rx), frame format 8N1.
--
-- The input line rxd is asynchronous to clk, so it first passes through two
-- flip-flops (synchronizer). Then an FSM with four states works:
--   IDLE  -> waits for the line to go '0' (possible start bit)
--   START -> waits 8 ticks (middle of the start bit) and checks it is still '0';
--            if not, it was a glitch and the FSM returns to IDLE
--   DATA  -> every 16 ticks (middle of each bit) samples the line, 8 times
--   STOP  -> after 16 ticks samples the stop bit:
--            '1' -> byte is valid (rx_valid), '0' -> framing error (rx_error)
-- Sampling in the middle of a bit gives the largest margin for clock mismatch.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity uart_rx is
    port (
        clk      : in  std_logic;                     -- system clock
        rst      : in  std_logic;                     -- synchronous reset, active high
        tick     : in  std_logic;                     -- 16x baud pulse from baud_gen
        rxd      : in  std_logic;                     -- serial input line (idle = '1')
        rx_data  : out std_logic_vector(7 downto 0);  -- received byte
        rx_valid : out std_logic;                     -- '1' for one clk: rx_data is valid
        rx_error : out std_logic                      -- '1' for one clk: stop bit was '0'
    );
end entity uart_rx;

architecture rtl of uart_rx is

    type state_t is (IDLE, START, DATA, STOP);
    signal state : state_t := IDLE;

    signal rxd_meta  : std_logic := '1';             -- first synchronizer flip-flop
    signal rxd_sync  : std_logic := '1';             -- second flip-flop: safe copy of rxd

    signal tick_cnt  : integer range 0 to 15 := 0;   -- counts ticks inside one bit
    signal bit_cnt   : integer range 0 to 7  := 0;   -- number of the data bit being received
    signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');  -- collects bits, LSB first

begin

    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                rxd_meta  <= '1';
                rxd_sync  <= '1';
                state     <= IDLE;
                tick_cnt  <= 0;
                bit_cnt   <= 0;
                shift_reg <= (others => '0');
                rx_data   <= (others => '0');
                rx_valid  <= '0';
                rx_error  <= '0';
            else
                -- two-stage synchronizer for the asynchronous input
                rxd_meta <= rxd;
                rxd_sync <= rxd_meta;

                rx_valid <= '0';                     -- default: no pulses
                rx_error <= '0';

                case state is

                    -- wait for the falling edge of the line
                    when IDLE =>
                        if rxd_sync = '0' then
                            tick_cnt <= 0;
                            state    <= START;
                        end if;

                    -- go to the middle of the start bit and check it
                    when START =>
                        if tick = '1' then
                            if tick_cnt = 7 then
                                if rxd_sync = '0' then
                                    tick_cnt <= 0;
                                    bit_cnt  <= 0;
                                    state    <= DATA;
                                else
                                    state <= IDLE;   -- short glitch, not a start bit
                                end if;
                            else
                                tick_cnt <= tick_cnt + 1;
                            end if;
                        end if;

                    -- sample 8 data bits in the middle of each bit;
                    -- the new bit enters from the left, so the first bit ends up in bit 0
                    when DATA =>
                        if tick = '1' then
                            if tick_cnt = 15 then
                                tick_cnt  <= 0;
                                shift_reg <= rxd_sync & shift_reg(7 downto 1);
                                if bit_cnt = 7 then
                                    state <= STOP;
                                else
                                    bit_cnt <= bit_cnt + 1;
                                end if;
                            else
                                tick_cnt <= tick_cnt + 1;
                            end if;
                        end if;

                    -- check the stop bit and publish the result
                    when STOP =>
                        if tick = '1' then
                            if tick_cnt = 15 then
                                tick_cnt <= 0;
                                if rxd_sync = '1' then
                                    rx_data  <= shift_reg;
                                    rx_valid <= '1';
                                else
                                    rx_error <= '1';
                                end if;
                                state <= IDLE;
                            else
                                tick_cnt <= tick_cnt + 1;
                            end if;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;
