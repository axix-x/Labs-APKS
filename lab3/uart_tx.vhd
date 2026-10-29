--------------------------------------------------------------------------------
-- uart_tx.vhd
-- UART transmitter (Tx), frame format 8N1:
--   1 start bit ('0'), 8 data bits (LSB first), no parity, 1 stop bit ('1').
--
-- The transmitter is a finite state machine (FSM) with four states:
--   IDLE  -> line is '1', waiting for tx_start
--   START -> sends the start bit '0'
--   DATA  -> sends 8 data bits, least significant bit first
--   STOP  -> sends the stop bit '1', then pulses tx_done
-- Every bit lasts 16 pulses of "tick" from baud_gen.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity uart_tx is
    port (
        clk      : in  std_logic;                     -- system clock
        rst      : in  std_logic;                     -- synchronous reset, active high
        tick     : in  std_logic;                     -- 16x baud pulse from baud_gen
        tx_start : in  std_logic;                     -- '1' for one clk: start sending tx_data
        tx_data  : in  std_logic_vector(7 downto 0);  -- byte to send
        txd      : out std_logic;                     -- serial output line (idle = '1')
        tx_busy  : out std_logic;                     -- '1' while a frame is being sent
        tx_done  : out std_logic                      -- '1' for one clk when the frame is finished
    );
end entity uart_tx;

architecture rtl of uart_tx is

    type state_t is (IDLE, START, DATA, STOP);
    signal state : state_t := IDLE;

    signal tick_cnt  : integer range 0 to 15 := 0;        -- counts ticks inside one bit
    signal bit_cnt   : integer range 0 to 7  := 0;        -- number of the data bit being sent
    signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');  -- copy of tx_data, shifted right
    signal txd_reg   : std_logic := '1';                  -- registered output, no glitches on the line

begin

    txd     <= txd_reg;
    tx_busy <= '0' when state = IDLE else '1';

    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state     <= IDLE;
                tick_cnt  <= 0;
                bit_cnt   <= 0;
                shift_reg <= (others => '0');
                txd_reg   <= '1';
                tx_done   <= '0';
            else
                tx_done <= '0';                      -- default: no "done" pulse

                case state is

                    -- line is idle; latch the byte when tx_start comes
                    when IDLE =>
                        txd_reg <= '1';
                        if tx_start = '1' then
                            shift_reg <= tx_data;
                            tick_cnt  <= 0;
                            state     <= START;
                        end if;

                    -- start bit: '0' for 16 ticks
                    when START =>
                        txd_reg <= '0';
                        if tick = '1' then
                            if tick_cnt = 15 then
                                tick_cnt <= 0;
                                bit_cnt  <= 0;
                                state    <= DATA;
                            else
                                tick_cnt <= tick_cnt + 1;
                            end if;
                        end if;

                    -- data bits: bit 0 of shift_reg is on the line,
                    -- after 16 ticks the register is shifted right
                    when DATA =>
                        txd_reg <= shift_reg(0);
                        if tick = '1' then
                            if tick_cnt = 15 then
                                tick_cnt  <= 0;
                                shift_reg <= '0' & shift_reg(7 downto 1);
                                if bit_cnt = 7 then
                                    state <= STOP;
                                else
                                    bit_cnt <= bit_cnt + 1;
                                end if;
                            else
                                tick_cnt <= tick_cnt + 1;
                            end if;
                        end if;

                    -- stop bit: '1' for 16 ticks, then report "done"
                    when STOP =>
                        txd_reg <= '1';
                        if tick = '1' then
                            if tick_cnt = 15 then
                                tick_cnt <= 0;
                                tx_done  <= '1';
                                state    <= IDLE;
                            else
                                tick_cnt <= tick_cnt + 1;
                            end if;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;
