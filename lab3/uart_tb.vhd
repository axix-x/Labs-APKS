--------------------------------------------------------------------------------
-- uart_tb.vhd
-- Testbench for the UART module (uart_top).
--
-- The testbench imitates the outside world:
--   * generates the 50 MHz clock and the reset;
--   * Test 1 (Tx): gives bytes to the transmitter and an independent monitor
--     reads the txd line bit by bit and compares the result;
--   * Test 2 (Rx): imitates another device that sends frames to the rxd line
--     at the nominal 115200 baud and checks what the receiver has collected;
--   * Test 3 (loopback): txd is connected to rxd, a byte goes Tx -> Rx;
--   * Test 4 (error): a frame with a wrong stop bit must raise rx_error.
-- Results are printed with "report"; the last line says how many errors.
--
-- FIRST_TEST (1..4) chooses which test runs first, the others follow in the
-- usual order. An online waveform viewer loads only the beginning of the run,
-- so the test that must be seen on the waveform is moved to the beginning.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tb is
end entity uart_tb;

architecture sim of uart_tb is

    constant CLK_FREQ_HZ : positive := 50_000_000;
    constant BAUD_RATE   : positive := 115_200;
    constant CLK_PERIOD  : time     := 20 ns;                  -- 50 MHz

    -- bit time of the device under test: 16 ticks * 27 clk * 20 ns
    constant DIVISOR      : positive := CLK_FREQ_HZ / (BAUD_RATE * 16);
    constant BIT_TIME_DUT : time     := 16 * DIVISOR * CLK_PERIOD;   -- 8640 ns
    -- bit time of the imitated external device: nominal 1 / 115200 s
    constant BIT_TIME_EXT : time     := 8680 ns;

    type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);
    constant TX_BYTES : byte_array_t := (x"55", x"A3", x"00", x"FF");
    constant RX_BYTES : byte_array_t := (x"A5", x"3C", x"81", x"7E");

    -- which test runs first: 1 = Tx, 2 = Rx, 3 = loopback, 4 = wrong stop bit
    constant FIRST_TEST : integer range 1 to 4 := 1;

    -- device under test signals
    signal clk      : std_logic := '0';
    signal rst      : std_logic := '1';
    signal tx_start : std_logic := '0';
    signal tx_data  : std_logic_vector(7 downto 0) := (others => '0');
    signal txd      : std_logic;
    signal tx_busy  : std_logic;
    signal tx_done  : std_logic;
    signal rxd      : std_logic;
    signal rx_data  : std_logic_vector(7 downto 0);
    signal rx_valid : std_logic;
    signal rx_error : std_logic;

    -- testbench helpers
    signal rxd_ext     : std_logic := '1';   -- line driven by the imitated external device
    signal loopback    : std_logic := '0';   -- '1': rxd is connected to txd
    signal sim_done    : boolean   := false; -- stops the clock at the end

    signal mon_tx_byte : std_logic_vector(7 downto 0) := (others => '0');  -- byte seen on txd
    signal mon_tx_cnt  : natural := 0;       -- how many frames the monitor has seen on txd
    signal mon_rx_byte : std_logic_vector(7 downto 0) := (others => '0');  -- last byte from the receiver
    signal mon_rx_cnt  : natural := 0;       -- how many rx_valid pulses
    signal mon_err_cnt : natural := 0;       -- how many rx_error pulses

begin

    -- device under test
    dut : entity work.uart_top
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ,
            BAUD_RATE   => BAUD_RATE
        )
        port map (
            clk      => clk,
            rst      => rst,
            tx_start => tx_start,
            tx_data  => tx_data,
            txd      => txd,
            tx_busy  => tx_busy,
            tx_done  => tx_done,
            rxd      => rxd,
            rx_data  => rx_data,
            rx_valid => rx_valid,
            rx_error => rx_error
        );

    -- receiver input: external device or loopback from the transmitter
    rxd <= txd when loopback = '1' else rxd_ext;

    -- clock generator
    clk_gen : process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- monitor of the txd line: works like an ideal external receiver
    tx_monitor : process
        variable v : std_logic_vector(7 downto 0);
    begin
        wait until falling_edge(txd);                 -- beginning of the start bit
        wait for BIT_TIME_DUT / 2;                    -- middle of the start bit
        assert txd = '0' report "TX monitor: start bit is not 0" severity error;
        for i in 0 to 7 loop
            wait for BIT_TIME_DUT;                    -- middle of data bit i
            v(i) := txd;                              -- LSB comes first
        end loop;
        wait for BIT_TIME_DUT;                        -- middle of the stop bit
        assert txd = '1' report "TX monitor: stop bit is not 1" severity error;
        mon_tx_byte <= v;
        mon_tx_cnt  <= mon_tx_cnt + 1;
    end process;

    -- monitor of the receiver outputs
    rx_monitor : process (clk)
    begin
        if rising_edge(clk) then
            if rx_valid = '1' then
                mon_rx_byte <= rx_data;
                mon_rx_cnt  <= mon_rx_cnt + 1;
            end if;
            if rx_error = '1' then
                mon_err_cnt <= mon_err_cnt + 1;
            end if;
        end if;
    end process;

    -- main test sequence
    stimulus : process

        variable errors : natural := 0;
        variable n_tx   : natural;
        variable n_rx   : natural;
        variable n_err  : natural;
        variable test   : integer range 1 to 4;

        -- imitates an external device: sends one frame to the rxd line
        procedure ext_send (
            constant data     : in std_logic_vector(7 downto 0);
            constant stop_bit : in std_logic
        ) is
        begin
            rxd_ext <= '0';                           -- start bit
            wait for BIT_TIME_EXT;
            for i in 0 to 7 loop
                rxd_ext <= data(i);                   -- data bits, LSB first
                wait for BIT_TIME_EXT;
            end loop;
            rxd_ext <= stop_bit;                      -- stop bit ('1' is correct)
            wait for BIT_TIME_EXT;
            rxd_ext <= '1';                           -- line is idle again
        end procedure;

        -- gives one byte to the transmitter and waits until the frame is sent
        procedure tx_send (
            constant data : in std_logic_vector(7 downto 0)
        ) is
        begin
            wait until rising_edge(clk);
            tx_data  <= data;
            tx_start <= '1';
            wait until rising_edge(clk);
            tx_start <= '0';
            wait until rising_edge(clk) and tx_done = '1';
            wait for 4 * CLK_PERIOD;                  -- let the monitors update
        end procedure;

    begin
        -- reset
        rst <= '1';
        wait for 10 * CLK_PERIOD;
        wait until rising_edge(clk);
        rst <= '0';
        wait for 10 * CLK_PERIOD;

        -- all four tests, starting with FIRST_TEST
        for step in 0 to 3 loop
            test := (FIRST_TEST - 1 + step) mod 4 + 1;
            case test is

            ------------------------------------------------------------------
            -- Test 1: transmitter. The monitor must read the same byte from txd.
            ------------------------------------------------------------------
            when 1 =>
                report "Test 1: transmitter (Tx)";
                for k in TX_BYTES'range loop
                    n_tx := mon_tx_cnt;
                    tx_send(TX_BYTES(k));
                    if mon_tx_byte = TX_BYTES(k) and mon_tx_cnt = n_tx + 1 then
                        report "  Tx OK: sent " & integer'image(to_integer(unsigned(TX_BYTES(k)))) &
                               ", seen on txd " & integer'image(to_integer(unsigned(mon_tx_byte)));
                    else
                        report "  Tx FAIL: sent " & integer'image(to_integer(unsigned(TX_BYTES(k)))) &
                               ", seen on txd " & integer'image(to_integer(unsigned(mon_tx_byte)))
                               severity error;
                        errors := errors + 1;
                    end if;
                    wait for BIT_TIME_DUT;                -- pause between frames
                end loop;

            ------------------------------------------------------------------
            -- Test 2: receiver. An external device sends frames to rxd.
            ------------------------------------------------------------------
            when 2 =>
                report "Test 2: receiver (Rx), external device at nominal baud rate";
                for k in RX_BYTES'range loop
                    n_rx := mon_rx_cnt;
                    ext_send(RX_BYTES(k), '1');
                    wait for 4 * CLK_PERIOD;
                    if mon_rx_cnt = n_rx + 1 and mon_rx_byte = RX_BYTES(k) then
                        report "  Rx OK: sent " & integer'image(to_integer(unsigned(RX_BYTES(k)))) &
                               ", received " & integer'image(to_integer(unsigned(mon_rx_byte)));
                    else
                        report "  Rx FAIL: sent " & integer'image(to_integer(unsigned(RX_BYTES(k)))) &
                               ", received " & integer'image(to_integer(unsigned(mon_rx_byte)))
                               severity error;
                        errors := errors + 1;
                    end if;
                    wait for BIT_TIME_EXT;                -- pause between frames
                end loop;

            ------------------------------------------------------------------
            -- Test 3: loopback. txd is connected to rxd: Tx -> Rx.
            ------------------------------------------------------------------
            when 3 =>
                report "Test 3: loopback Tx -> Rx";
                loopback <= '1';
                wait for 4 * CLK_PERIOD;                  -- both lines are idle ('1'), no glitch
                n_rx := mon_rx_cnt;
                tx_send(x"C5");
                if mon_rx_cnt = n_rx + 1 and mon_rx_byte = x"C5" then
                    report "  Loopback OK: sent 197, received " &
                           integer'image(to_integer(unsigned(mon_rx_byte)));
                else
                    report "  Loopback FAIL: sent 197, received " &
                           integer'image(to_integer(unsigned(mon_rx_byte))) severity error;
                    errors := errors + 1;
                end if;
                loopback <= '0';
                wait for BIT_TIME_DUT;

            ------------------------------------------------------------------
            -- Test 4: framing error. Stop bit is '0': rx_error, no rx_valid.
            ------------------------------------------------------------------
            when 4 =>
                report "Test 4: frame with a wrong stop bit";
                n_rx  := mon_rx_cnt;
                n_err := mon_err_cnt;
                ext_send(x"0F", '0');
                wait for 4 * CLK_PERIOD;
                if mon_err_cnt = n_err + 1 and mon_rx_cnt = n_rx then
                    report "  Error detection OK: rx_error raised, byte not accepted";
                else
                    report "  Error detection FAIL" severity error;
                    errors := errors + 1;
                end if;
                wait for 2 * BIT_TIME_EXT;

            end case;
        end loop;

        ------------------------------------------------------------------
        if errors = 0 then
            report "ALL TESTS PASSED";
        else
            report "TESTS FAILED, errors: " & integer'image(errors) severity error;
        end if;
        sim_done <= true;
        wait;
    end process;

end architecture sim;
