library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.matrix_accel_config_pkg.all;

entity tb_command_interface is
end entity tb_command_interface;

architecture sim of tb_command_interface is

    constant CLK_PERIOD   : time := 10 ns;
    constant ADDR_WIDTH   : positive := 10;
    constant DATA_WIDTH   : positive := 32;
    constant COUNTER_WIDTH : positive := 64;

    constant CMD_LOAD_A        : std_logic_vector(7 downto 0) := x"41";
    constant CMD_LOAD_B        : std_logic_vector(7 downto 0) := x"42";
    constant CMD_STREAM_A      : std_logic_vector(7 downto 0) := x"61";
    constant CMD_STREAM_C      : std_logic_vector(7 downto 0) := x"72";
    constant CMD_START         : std_logic_vector(7 downto 0) := x"53";
    constant CMD_READ_C        : std_logic_vector(7 downto 0) := x"52";
    constant CMD_READ_STATUS   : std_logic_vector(7 downto 0) := x"3F";
    constant CMD_READ_COUNTERS : std_logic_vector(7 downto 0) := x"50";
    constant CMD_READ_TELEMETRY : std_logic_vector(7 downto 0) := x"54";
    constant RESP_ACK          : std_logic_vector(7 downto 0) := x"06";

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal rx_valid : std_logic := '0';
    signal rx_byte  : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_ready : std_logic;
    signal tx_busy  : std_logic := '0';
    signal tx_start : std_logic;
    signal tx_byte  : std_logic_vector(7 downto 0);

    signal accelerator_busy : std_logic := '0';
    signal accelerator_done : std_logic := '0';
    signal accelerator_load_active : std_logic := '0';
    signal accelerator_compute_active : std_logic := '0';
    signal accelerator_store_active : std_logic := '0';
    signal accelerator_error : std_logic := '0';

    signal host_cmd_valid  : std_logic;
    signal host_cmd_write  : std_logic;
    signal host_cmd_ready  : std_logic := '0';
    signal host_matrix_sel : std_logic_vector(1 downto 0);
    signal host_addr       : unsigned(ADDR_WIDTH-1 downto 0);
    signal host_data_in    : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal host_data_out   : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal host_rd_valid   : std_logic := '0';
    signal start           : std_logic;
    signal clear           : std_logic;

    signal perf_total_cycles        : unsigned(COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal perf_load_cycles         : unsigned(COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal perf_compute_cycles      : unsigned(COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal perf_store_cycles        : unsigned(COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal perf_num_tiles_processed : unsigned(COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal perf_num_mac_ops_issued  : unsigned(COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal debug_stream_c_active    : std_logic;
    signal debug_wait_read_c        : std_logic;

    procedure send_byte(
        signal valid_sig : out std_logic;
        signal byte_sig  : out std_logic_vector(7 downto 0);
        constant value   : std_logic_vector(7 downto 0)
    ) is
    begin
        byte_sig  <= value;
        valid_sig <= '1';
        wait until rising_edge(clk);
        valid_sig <= '0';
        wait until rising_edge(clk);
    end procedure;

    procedure send_word32(
        signal valid_sig : out std_logic;
        signal byte_sig  : out std_logic_vector(7 downto 0);
        constant value   : std_logic_vector(31 downto 0)
    ) is
    begin
        send_byte(valid_sig, byte_sig, value(31 downto 24));
        send_byte(valid_sig, byte_sig, value(23 downto 16));
        send_byte(valid_sig, byte_sig, value(15 downto 8));
        send_byte(valid_sig, byte_sig, value(7 downto 0));
    end procedure;

    procedure expect_tx_byte(
        signal start_sig : in std_logic;
        signal byte_sig  : in std_logic_vector(7 downto 0);
        constant expected : std_logic_vector(7 downto 0);
        constant label_text : string
    ) is
    begin
        for cycle_idx in 0 to 100 loop
            wait until rising_edge(clk);
            wait for 1 ns;

            if start_sig = '1' then
                assert byte_sig = expected
                    report label_text & ": byte UART incorreto."
                    severity failure;
                return;
            end if;
        end loop;

        assert false
            report label_text & ": timeout aguardando byte UART."
            severity failure;
    end procedure;

    procedure expect_tx_word32(
        signal start_sig : in std_logic;
        signal byte_sig  : in std_logic_vector(7 downto 0);
        constant expected : std_logic_vector(31 downto 0);
        constant label_text : string
    ) is
    begin
        expect_tx_byte(start_sig, byte_sig, expected(31 downto 24), label_text & " byte 0");
        expect_tx_byte(start_sig, byte_sig, expected(23 downto 16), label_text & " byte 1");
        expect_tx_byte(start_sig, byte_sig, expected(15 downto 8), label_text & " byte 2");
        expect_tx_byte(start_sig, byte_sig, expected(7 downto 0), label_text & " byte 3");
    end procedure;

    procedure wait_host_write(
        signal valid_sig : in std_logic;
        signal write_sig : in std_logic;
        signal ready_sig : out std_logic;
        signal sel_sig   : in std_logic_vector(1 downto 0);
        signal addr_sig  : in unsigned;
        signal data_sig  : in std_logic_vector;
        constant expected_sel  : std_logic_vector(1 downto 0);
        constant expected_addr : natural;
        constant expected_data : std_logic_vector(31 downto 0);
        constant label_text    : string
    ) is
    begin
        ready_sig <= '0';

        for cycle_idx in 0 to 100 loop
            wait until rising_edge(clk);
            wait for 1 ns;

            if valid_sig = '1' and write_sig = '1' then
                assert sel_sig = expected_sel
                    report label_text & ": host_matrix_sel incorreto."
                    severity failure;

                assert to_integer(addr_sig) = expected_addr
                    report label_text & ": host_addr incorreto."
                    severity failure;

                assert data_sig = expected_data
                    report label_text & ": host_data_in incorreto."
                    severity failure;

                ready_sig <= '1';
                wait until rising_edge(clk);
                ready_sig <= '0';
                return;
            end if;
        end loop;

        assert false
            report label_text & ": timeout aguardando host_cmd_valid write."
            severity failure;
    end procedure;

    procedure wait_host_read(
        signal valid_sig : in std_logic;
        signal write_sig : in std_logic;
        signal ready_sig : out std_logic;
        signal addr_sig  : in unsigned;
        constant expected_addr : natural;
        constant label_text    : string
    ) is
    begin
        ready_sig <= '0';

        for cycle_idx in 0 to 100 loop
            wait until rising_edge(clk);
            wait for 1 ns;

            if valid_sig = '1' and write_sig = '0' then
                assert to_integer(addr_sig) = expected_addr
                    report label_text & ": host_addr incorreto."
                    severity failure;

                ready_sig <= '1';
                wait until rising_edge(clk);
                ready_sig <= '0';
                return;
            end if;
        end loop;

        assert false
            report label_text & ": timeout aguardando host_cmd_valid read."
            severity failure;
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.command_interface
        generic map (
            ADDR_WIDTH        => ADDR_WIDTH,
            DATA_WIDTH        => DATA_WIDTH,
            CLK_FREQ_HZ       => 50000000,
            COUNTER_WIDTH     => COUNTER_WIDTH,
            STREAM_C_READ_GAP_CYCLES => 0
        )
        port map (
            clk                      => clk,
            rst                      => rst,
            rx_valid                 => rx_valid,
            rx_byte                  => rx_byte,
            rx_ready                 => rx_ready,
            tx_busy                  => tx_busy,
            tx_start                 => tx_start,
            tx_byte                  => tx_byte,
            accelerator_busy         => accelerator_busy,
            accelerator_done         => accelerator_done,
            accelerator_load_active  => accelerator_load_active,
            accelerator_compute_active => accelerator_compute_active,
            accelerator_store_active => accelerator_store_active,
            accelerator_error        => accelerator_error,
            host_cmd_valid           => host_cmd_valid,
            host_cmd_write           => host_cmd_write,
            host_cmd_ready           => host_cmd_ready,
            host_matrix_sel          => host_matrix_sel,
            host_addr                => host_addr,
            host_data_in             => host_data_in,
            host_data_out            => host_data_out,
            host_rd_valid            => host_rd_valid,
            start                    => start,
            clear                    => clear,
            perf_total_cycles        => perf_total_cycles,
            perf_load_cycles         => perf_load_cycles,
            perf_compute_cycles      => perf_compute_cycles,
            perf_store_cycles        => perf_store_cycles,
            perf_num_tiles_processed => perf_num_tiles_processed,
            perf_num_mac_ops_issued  => perf_num_mac_ops_issued,
            debug_stream_c_active    => debug_stream_c_active,
            debug_wait_read_c        => debug_wait_read_c
        );

    stim_proc : process
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        send_byte(rx_valid, rx_byte, CMD_LOAD_A);
        send_word32(rx_valid, rx_byte, x"00000005");
        send_word32(rx_valid, rx_byte, x"0000002A");
        wait_host_write(host_cmd_valid, host_cmd_write, host_cmd_ready,
                        host_matrix_sel, host_addr, host_data_in,
                        MATRIX_ID_A, 5, x"0000002A", "LOAD_A");
        expect_tx_byte(tx_start, tx_byte, RESP_ACK, "LOAD_A ACK");

        send_byte(rx_valid, rx_byte, CMD_LOAD_B);
        send_word32(rx_valid, rx_byte, x"00000006");
        send_word32(rx_valid, rx_byte, x"FFFFFFF9");
        wait_host_write(host_cmd_valid, host_cmd_write, host_cmd_ready,
                        host_matrix_sel, host_addr, host_data_in,
                        MATRIX_ID_B, 6, x"FFFFFFF9", "LOAD_B");
        expect_tx_byte(tx_start, tx_byte, RESP_ACK, "LOAD_B ACK");

        send_byte(rx_valid, rx_byte, CMD_STREAM_A);
        send_word32(rx_valid, rx_byte, x"00000008");
        send_byte(rx_valid, rx_byte, x"00");
        send_byte(rx_valid, rx_byte, x"03");

        send_byte(rx_valid, rx_byte, x"01");
        wait_host_write(host_cmd_valid, host_cmd_write, host_cmd_ready,
                        host_matrix_sel, host_addr, host_data_in,
                        MATRIX_ID_A, 8, x"00000001", "STREAM_A[0]");

        send_byte(rx_valid, rx_byte, x"FE");
        wait_host_write(host_cmd_valid, host_cmd_write, host_cmd_ready,
                        host_matrix_sel, host_addr, host_data_in,
                        MATRIX_ID_A, 9, x"000000FE", "STREAM_A[1]");

        send_byte(rx_valid, rx_byte, x"7F");
        wait_host_write(host_cmd_valid, host_cmd_write, host_cmd_ready,
                        host_matrix_sel, host_addr, host_data_in,
                        MATRIX_ID_A, 10, x"0000007F", "STREAM_A[2]");
        expect_tx_byte(tx_start, tx_byte, RESP_ACK, "STREAM_A ACK");

        accelerator_busy <= '0';
        host_cmd_ready <= '1';
        send_byte(rx_valid, rx_byte, CMD_START);
        wait for 1 ns;

        if start /= '1' then
            for cycle_idx in 0 to 100 loop
                wait until rising_edge(clk);
                wait for 1 ns;

                if start = '1' then
                    exit;
                end if;

                assert cycle_idx < 100
                    report "START nao gerou pulso start."
                    severity failure;
            end loop;
        end if;

        expect_tx_byte(tx_start, tx_byte, RESP_ACK, "START ACK");
        host_cmd_ready <= '0';

        accelerator_busy <= '1';
        accelerator_done <= '0';
        send_byte(rx_valid, rx_byte, CMD_READ_STATUS);
        expect_tx_byte(tx_start, tx_byte, x"00", "READ_STATUS byte 0");
        expect_tx_byte(tx_start, tx_byte, x"00", "READ_STATUS byte 1");
        expect_tx_byte(tx_start, tx_byte, x"00", "READ_STATUS byte 2");
        expect_tx_byte(tx_start, tx_byte, x"01", "READ_STATUS byte 3");

        host_data_out <= x"00000099";
        send_byte(rx_valid, rx_byte, CMD_READ_C);
        send_word32(rx_valid, rx_byte, x"00000007");
        wait_host_read(host_cmd_valid, host_cmd_write, host_cmd_ready,
                       host_addr, 7, "READ_C");
        wait until rising_edge(clk);
        host_rd_valid <= '1';
        wait until rising_edge(clk);
        host_rd_valid <= '0';
        expect_tx_byte(tx_start, tx_byte, x"00", "READ_C byte 0");
        expect_tx_byte(tx_start, tx_byte, x"00", "READ_C byte 1");
        expect_tx_byte(tx_start, tx_byte, x"00", "READ_C byte 2");
        expect_tx_byte(tx_start, tx_byte, x"99", "READ_C byte 3");

        send_byte(rx_valid, rx_byte, CMD_STREAM_C);
        send_word32(rx_valid, rx_byte, x"0000000C");
        send_byte(rx_valid, rx_byte, x"00");
        send_byte(rx_valid, rx_byte, x"03");

        host_data_out <= x"00000011";
        wait_host_read(host_cmd_valid, host_cmd_write, host_cmd_ready,
                       host_addr, 12, "STREAM_C[0]");
        wait until rising_edge(clk);
        host_rd_valid <= '1';
        wait until rising_edge(clk);
        host_rd_valid <= '0';
        expect_tx_byte(tx_start, tx_byte, RESP_ACK, "STREAM_C ACK");
        expect_tx_byte(tx_start, tx_byte, x"00", "STREAM_C[0] byte 0");
        expect_tx_byte(tx_start, tx_byte, x"00", "STREAM_C[0] byte 1");
        expect_tx_byte(tx_start, tx_byte, x"00", "STREAM_C[0] byte 2");
        expect_tx_byte(tx_start, tx_byte, x"11", "STREAM_C[0] byte 3");

        host_data_out <= x"FFFFFFFE";
        wait_host_read(host_cmd_valid, host_cmd_write, host_cmd_ready,
                       host_addr, 13, "STREAM_C[1]");
        wait until rising_edge(clk);
        host_rd_valid <= '1';
        wait until rising_edge(clk);
        host_rd_valid <= '0';
        expect_tx_byte(tx_start, tx_byte, x"FF", "STREAM_C[1] byte 0");
        expect_tx_byte(tx_start, tx_byte, x"FF", "STREAM_C[1] byte 1");
        expect_tx_byte(tx_start, tx_byte, x"FF", "STREAM_C[1] byte 2");
        expect_tx_byte(tx_start, tx_byte, x"FE", "STREAM_C[1] byte 3");

        host_data_out <= x"0000007F";
        wait_host_read(host_cmd_valid, host_cmd_write, host_cmd_ready,
                       host_addr, 14, "STREAM_C[2]");
        wait until rising_edge(clk);
        host_rd_valid <= '1';
        wait until rising_edge(clk);
        host_rd_valid <= '0';
        expect_tx_byte(tx_start, tx_byte, x"00", "STREAM_C[2] byte 0");
        expect_tx_byte(tx_start, tx_byte, x"00", "STREAM_C[2] byte 1");
        expect_tx_byte(tx_start, tx_byte, x"00", "STREAM_C[2] byte 2");
        expect_tx_byte(tx_start, tx_byte, x"7F", "STREAM_C[2] byte 3");

        perf_total_cycles        <= to_unsigned(1, COUNTER_WIDTH);
        perf_load_cycles         <= to_unsigned(2, COUNTER_WIDTH);
        perf_compute_cycles      <= to_unsigned(3, COUNTER_WIDTH);
        perf_store_cycles        <= to_unsigned(4, COUNTER_WIDTH);
        perf_num_tiles_processed <= to_unsigned(5, COUNTER_WIDTH);
        perf_num_mac_ops_issued  <= to_unsigned(6, COUNTER_WIDTH);

        send_byte(rx_valid, rx_byte, CMD_READ_COUNTERS);

        for word_idx in 1 to 6 loop
            expect_tx_byte(tx_start, tx_byte, x"00", "READ_COUNTERS byte 0");
            expect_tx_byte(tx_start, tx_byte, x"00", "READ_COUNTERS byte 1");
            expect_tx_byte(tx_start, tx_byte, x"00", "READ_COUNTERS byte 2");
            expect_tx_byte(tx_start, tx_byte, std_logic_vector(to_unsigned(word_idx, 8)), "READ_COUNTERS byte 3");
        end loop;

        send_byte(rx_valid, rx_byte, CMD_READ_TELEMETRY);
        expect_tx_word32(tx_start, tx_byte, x"00000001", "READ_TELEMETRY status");
        expect_tx_word32(tx_start, tx_byte, x"02FAF080", "READ_TELEMETRY clk_freq_hz");
        expect_tx_word32(tx_start, tx_byte, x"00000001", "READ_TELEMETRY total_cycles");
        expect_tx_word32(tx_start, tx_byte, x"00000002", "READ_TELEMETRY load_cycles");
        expect_tx_word32(tx_start, tx_byte, x"00000003", "READ_TELEMETRY compute_cycles");
        expect_tx_word32(tx_start, tx_byte, x"00000004", "READ_TELEMETRY store_cycles");
        expect_tx_word32(tx_start, tx_byte, x"00000005", "READ_TELEMETRY tiles");
        expect_tx_word32(tx_start, tx_byte, x"00000006", "READ_TELEMETRY mac_ops");

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
