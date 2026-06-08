library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.matrix_accel_config_pkg.all;

entity tb_matrix_accelerator_full_top_uart_protocol is
    generic (
        N                   : positive := DEFAULT_N;
        TILE_SIZE           : positive := DEFAULT_TILE_SIZE;
        NUM_MACS            : positive := DEFAULT_NUM_MACS;
        DATA_WIDTH          : positive := DEFAULT_DATA_WIDTH;
        ACC_WIDTH           : positive := DEFAULT_ACC_WIDTH;
        MEM_TYPE            : string   := "internal_fpga_ram";
        DATAFLOW            : string   := "output_stationary";
        BUFFERING_MODE      : string   := "single";
        MEMORY_BURST_LEN    : natural  := 1;
        MAC_PIPELINE_STAGES : natural  := 0;
        MEMORY_BANKS_A      : positive := 1;
        MEMORY_BANKS_B      : positive := 1;
        CLKS_PER_BIT        : positive := 8;
        CLK_FREQ_HZ         : positive := 1000;
        UART_FIFO_DEPTH     : positive := 64;
        MAX_STATUS_POLLS    : positive := 5000;
        NUM_TESTS           : positive := 3
    );
end entity tb_matrix_accelerator_full_top_uart_protocol;

architecture sim of tb_matrix_accelerator_full_top_uart_protocol is

    constant CLK_PERIOD : time := 10 ns;

    constant CMD_LOAD_A        : std_logic_vector(7 downto 0) := x"41"; -- 'A'
    constant CMD_LOAD_B        : std_logic_vector(7 downto 0) := x"42"; -- 'B'
    constant CMD_STREAM_A      : std_logic_vector(7 downto 0) := x"61"; -- 'a'
    constant CMD_STREAM_B      : std_logic_vector(7 downto 0) := x"62"; -- 'b'
    constant CMD_STREAM_C      : std_logic_vector(7 downto 0) := x"72"; -- 'r'
    constant CMD_CLEAR         : std_logic_vector(7 downto 0) := x"43"; -- 'C'
    constant CMD_START         : std_logic_vector(7 downto 0) := x"53"; -- 'S'
    constant CMD_READ_STATUS   : std_logic_vector(7 downto 0) := x"3F"; -- '?'
    constant CMD_READ_C        : std_logic_vector(7 downto 0) := x"52"; -- 'R'
    constant CMD_READ_COUNTERS : std_logic_vector(7 downto 0) := x"50"; -- 'P'

    constant RESP_ACK : std_logic_vector(7 downto 0) := x"06";
    constant RESP_NAK : std_logic_vector(7 downto 0) := x"15";

    constant STATUS_BUSY_BIT : natural := 0;
    constant STATUS_DONE_BIT : natural := 1;
    constant STREAM_C_CHUNK_ELEMS : natural := 4096;

    signal clk          : std_logic := '0';
    signal rst          : std_logic := '0';
    signal uart_rx_i    : std_logic := '1';
    signal uart_tx_o    : std_logic;
    signal start_button : std_logic := '0';

    signal LEDR : std_logic_vector(9 downto 0);
    signal HEX0 : std_logic_vector(6 downto 0);
    signal HEX1 : std_logic_vector(6 downto 0);
    signal HEX2 : std_logic_vector(6 downto 0);
    signal HEX3 : std_logic_vector(6 downto 0);
    signal HEX4 : std_logic_vector(6 downto 0);
    signal HEX5 : std_logic_vector(6 downto 0);
    signal DRAM_ADDR  : std_logic_vector(12 downto 0);
    signal DRAM_BA    : std_logic_vector(1 downto 0);
    signal DRAM_CAS_N : std_logic;
    signal DRAM_CKE   : std_logic;
    signal DRAM_CLK   : std_logic;
    signal DRAM_CS_N  : std_logic;
    signal DRAM_DQ    : std_logic_vector(15 downto 0);
    signal DRAM_LDQM  : std_logic;
    signal DRAM_RAS_N : std_logic;
    signal DRAM_UDQM  : std_logic;
    signal DRAM_WE_N  : std_logic;

    function a_value(
        constant row_idx : natural;
        constant col_idx : natural
    ) return integer is
        variable selector : natural;
    begin
        selector := (row_idx + 2 * col_idx + 1) mod 3;

        case selector is
            when 0 =>
                return -1;
            when 1 =>
                return 0;
            when others =>
                return 1;
        end case;
    end function;

    function b_value(
        constant row_idx : natural;
        constant col_idx : natural
    ) return integer is
        variable selector : natural;
    begin
        selector := (2 * row_idx + col_idx + 2) mod 3;

        case selector is
            when 0 =>
                return 1;
            when 1 =>
                return -1;
            when others =>
                return 0;
        end case;
    end function;

    function expected_c_value(
        constant row_idx : natural;
        constant col_idx : natural
    ) return integer is
        variable acc : integer := 0;
    begin
        for k in 0 to N - 1 loop
            acc := acc + a_value(row_idx, k) * b_value(k, col_idx);
        end loop;

        return acc;
    end function;

    procedure wait_cycles(constant count : natural) is
    begin
        for idx in 1 to count loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

    procedure uart_send_byte(
        signal rx_line : out std_logic;
        constant value : std_logic_vector(7 downto 0)
    ) is
    begin
        wait until rising_edge(clk);

        rx_line <= '0';
        wait_cycles(CLKS_PER_BIT);

        for bit_idx in 0 to 7 loop
            rx_line <= value(bit_idx);
            wait_cycles(CLKS_PER_BIT);
        end loop;

        rx_line <= '1';
        wait_cycles(CLKS_PER_BIT);
    end procedure;

    procedure uart_read_byte(
        signal tx_line : in std_logic;
        variable value : out std_logic_vector(7 downto 0);
        constant label_msg : string := "UART read"
    ) is
        variable timeout_cycles : natural := 0;
        constant MAX_WAIT_CYCLES : natural := 5000;
    begin
        while tx_line /= '0' loop
            wait until rising_edge(clk);
            timeout_cycles := timeout_cycles + 1;

            assert timeout_cycles < MAX_WAIT_CYCLES
                report label_msg & ": timeout esperando start bit em uart_tx_o"
                severity failure;
        end loop;

        -- sample near center of first data bit
        wait_cycles(CLKS_PER_BIT + (CLKS_PER_BIT / 2));

        for bit_idx in 0 to 7 loop
            value(bit_idx) := tx_line;

            if bit_idx < 7 then
                wait_cycles(CLKS_PER_BIT);
            end if;
        end loop;

        wait_cycles(CLKS_PER_BIT);

        assert tx_line = '1'
            report label_msg & ": UART TX stop bit nao esta em nivel alto."
            severity failure;
    end procedure;

    procedure uart_send_word_be(
        signal rx_line : out std_logic;
        constant value : std_logic_vector(31 downto 0)
    ) is
    begin
        uart_send_byte(rx_line, value(31 downto 24));
        uart_send_byte(rx_line, value(23 downto 16));
        uart_send_byte(rx_line, value(15 downto 8));
        uart_send_byte(rx_line, value(7 downto 0));
    end procedure;

    procedure uart_read_word_be(
        signal tx_line : in std_logic;
        variable value : out std_logic_vector(31 downto 0)
    ) is
        variable b0 : std_logic_vector(7 downto 0);
        variable b1 : std_logic_vector(7 downto 0);
        variable b2 : std_logic_vector(7 downto 0);
        variable b3 : std_logic_vector(7 downto 0);
    begin
        uart_read_byte(tx_line, b0);
        uart_read_byte(tx_line, b1);
        uart_read_byte(tx_line, b2);
        uart_read_byte(tx_line, b3);

        value := b0 & b1 & b2 & b3;
    end procedure;

    procedure uart_expect_byte(
        signal tx_line : in std_logic;
        constant expected : std_logic_vector(7 downto 0);
        constant label_msg : string
    ) is
        variable got : std_logic_vector(7 downto 0);
    begin
        uart_read_byte(tx_line, got);

        assert got = expected
            report label_msg &
                   ". Esperado=" & integer'image(to_integer(unsigned(expected))) &
                   " recebido=" & integer'image(to_integer(unsigned(got)))
            severity failure;
    end procedure;

    procedure uart_write_matrix_word(
        signal rx_line : out std_logic;
        signal tx_line : in std_logic;
        constant cmd   : std_logic_vector(7 downto 0);
        constant addr  : natural;
        constant value : integer
    ) is
    begin
        uart_send_byte(rx_line, cmd);
        uart_send_word_be(rx_line, std_logic_vector(to_unsigned(addr, 32)));
        uart_send_word_be(rx_line, std_logic_vector(to_signed(value, 32)));

        uart_expect_byte(tx_line, RESP_ACK, "LOAD deveria retornar ACK");
    end procedure;

    procedure uart_stream_matrix_i8(
        signal rx_line : out std_logic;
        signal tx_line : in std_logic;
        constant cmd   : std_logic_vector(7 downto 0);
        constant use_a : boolean
    ) is
        variable value      : integer;
        variable count_word : std_logic_vector(15 downto 0);
    begin
        count_word := std_logic_vector(to_unsigned(N * N, 16));

        uart_send_byte(rx_line, cmd);
        uart_send_word_be(rx_line, x"00000000");
        uart_send_byte(rx_line, count_word(15 downto 8));
        uart_send_byte(rx_line, count_word(7 downto 0));

        for row_idx in 0 to N - 1 loop
            for col_idx in 0 to N - 1 loop
                if use_a then
                    value := a_value(row_idx, col_idx);
                else
                    value := b_value(row_idx, col_idx);
                end if;

                uart_send_byte(rx_line, std_logic_vector(to_signed(value, 8)));
            end loop;
        end loop;

        uart_expect_byte(tx_line, RESP_ACK, "STREAM deveria retornar ACK");
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.matrix_accelerator_full_top
        generic map (
            N                   => N,
            TILE_SIZE           => TILE_SIZE,
            NUM_MACS            => NUM_MACS,
            DATA_WIDTH          => DATA_WIDTH,
            ACC_WIDTH           => ACC_WIDTH,
            MEM_TYPE            => MEM_TYPE,
            DATAFLOW            => DATAFLOW,
            BUFFERING_MODE      => BUFFERING_MODE,
            MEMORY_BURST_LEN    => MEMORY_BURST_LEN,
            MAC_PIPELINE_STAGES => MAC_PIPELINE_STAGES,
            MEMORY_BANKS_A      => MEMORY_BANKS_A,
            MEMORY_BANKS_B      => MEMORY_BANKS_B,
            CLKS_PER_BIT        => CLKS_PER_BIT,
            CLK_FREQ_HZ         => CLK_FREQ_HZ,
            UART_FIFO_DEPTH     => UART_FIFO_DEPTH,
            SDRAM_SIMULATION_MODEL => true,
            ENABLE_SIGNALTAP    => false
        )
        port map (
            clk          => clk,
            rst          => rst,
            uart_rx_i    => uart_rx_i,
            uart_tx_o    => uart_tx_o,
            start_button => start_button,
            LEDR         => LEDR,
            HEX0         => HEX0,
            HEX1         => HEX1,
            HEX2         => HEX2,
            HEX3         => HEX3,
            HEX4         => HEX4,
            HEX5         => HEX5,
            DRAM_ADDR    => DRAM_ADDR,
            DRAM_BA      => DRAM_BA,
            DRAM_CAS_N   => DRAM_CAS_N,
            DRAM_CKE     => DRAM_CKE,
            DRAM_CLK     => DRAM_CLK,
            DRAM_CS_N    => DRAM_CS_N,
            DRAM_DQ      => DRAM_DQ,
            DRAM_LDQM    => DRAM_LDQM,
            DRAM_RAS_N   => DRAM_RAS_N,
            DRAM_UDQM    => DRAM_UDQM,
            DRAM_WE_N    => DRAM_WE_N
        );

    stim_proc : process
        variable status_word  : std_logic_vector(31 downto 0);
        variable result_word  : std_logic_vector(31 downto 0);
        variable counter_word : std_logic_vector(31 downto 0);
        variable count_word   : std_logic_vector(15 downto 0);

        variable addr         : natural;
        variable chunk_count  : natural;
        variable linear_addr  : natural;
        variable row_calc     : natural;
        variable col_calc     : natural;
        variable got_int      : integer;
        variable exp_int      : integer;
        variable done_seen    : boolean := false;
    begin
        assert N mod TILE_SIZE = 0
            report "N precisa ser multiplo de TILE_SIZE."
            severity failure;

        assert DATA_WIDTH >= 2
            report "Este testbench usa valores -1, 0 e 1; DATA_WIDTH precisa ser pelo menos 2."
            severity failure;

        report "SIM: reset inicial" severity note;
        report "SIM: generics N=" & integer'image(N) &
               " TILE_SIZE=" & integer'image(TILE_SIZE) &
               " NUM_MACS=" & integer'image(NUM_MACS) &
               " DATA_WIDTH=" & integer'image(DATA_WIDTH) &
               " ACC_WIDTH=" & integer'image(ACC_WIDTH) &
               " CLKS_PER_BIT=" & integer'image(CLKS_PER_BIT)
               severity note;

        rst <= '1';
        uart_rx_i <= '1';
        start_button <= '0';
        wait_cycles(10);

        rst <= '0';
        wait_cycles(10);

        assert uart_tx_o = '1'
            report "uart_tx_o deveria estar em repouso alto depois do reset."
            severity failure;

        report "SIM: testando comando invalido -> NAK" severity note;
        uart_send_byte(uart_rx_i, x"00");
        uart_expect_byte(uart_tx_o, RESP_NAK, "Comando invalido deveria retornar NAK");

        for test_idx in 0 to NUM_TESTS - 1 loop
            report "SIM: TEST " & integer'image(test_idx) & " CLEAR" severity note;
            uart_send_byte(uart_rx_i, CMD_CLEAR);
            uart_expect_byte(uart_tx_o, RESP_ACK, "CLEAR deveria retornar ACK");

            report "SIM: TEST " & integer'image(test_idx) & " carregando matriz A via UART streaming" severity note;
            uart_stream_matrix_i8(uart_rx_i, uart_tx_o, CMD_STREAM_A, true);

            report "SIM: TEST " & integer'image(test_idx) & " carregando matriz B via UART streaming" severity note;
            uart_stream_matrix_i8(uart_rx_i, uart_tx_o, CMD_STREAM_B, false);

            report "SIM: TEST " & integer'image(test_idx) & " enviando START via UART" severity note;

            uart_send_byte(uart_rx_i, CMD_START);
            uart_expect_byte(uart_tx_o, RESP_ACK, "START deveria retornar ACK");

            report "SIM: TEST " & integer'image(test_idx) & " aguardando done por READ_STATUS" severity note;

            done_seen := false;

            for poll_idx in 0 to MAX_STATUS_POLLS loop
                uart_send_byte(uart_rx_i, CMD_READ_STATUS);
                uart_read_word_be(uart_tx_o, status_word);

                if status_word(STATUS_DONE_BIT) = '1' then
                    done_seen := true;
                    exit;
                end if;

                wait_cycles(50);
            end loop;

            assert done_seen
                report "Acelerador nao sinalizou done via READ_STATUS."
                severity failure;

            report "SIM: TEST " & integer'image(test_idx) & " lendo matriz C via UART streaming" severity note;

            addr := 0;
            while addr < N * N loop
                chunk_count := N * N - addr;
                if chunk_count > STREAM_C_CHUNK_ELEMS then
                    chunk_count := STREAM_C_CHUNK_ELEMS;
                end if;

                count_word := std_logic_vector(to_unsigned(chunk_count, 16));
                uart_send_byte(uart_rx_i, CMD_STREAM_C);
                uart_send_word_be(uart_rx_i, std_logic_vector(to_unsigned(addr, 32)));
                uart_send_byte(uart_rx_i, count_word(15 downto 8));
                uart_send_byte(uart_rx_i, count_word(7 downto 0));
                uart_expect_byte(uart_tx_o, RESP_ACK, "STREAM_C deveria retornar ACK antes dos dados");

                for chunk_offset in 0 to chunk_count - 1 loop
                    uart_read_word_be(uart_tx_o, result_word);

                    linear_addr := addr + chunk_offset;
                    row_calc := linear_addr / N;
                    col_calc := linear_addr mod N;
                    got_int := to_integer(signed(result_word));
                    exp_int := expected_c_value(row_calc, col_calc);

                    assert got_int = exp_int
                        report "Resultado C incorreto em addr=" &
                               integer'image(linear_addr) &
                               " row=" & integer'image(row_calc) &
                               " col=" & integer'image(col_calc) &
                               ". Esperado=" & integer'image(exp_int) &
                               " recebido=" & integer'image(got_int)
                        severity failure;
                end loop;

                addr := addr + chunk_count;
            end loop;

            report "SIM: TEST " & integer'image(test_idx) & " lendo contadores de performance" severity note;

            uart_send_byte(uart_rx_i, CMD_READ_COUNTERS);

            for counter_idx in 0 to 5 loop
                uart_read_word_be(uart_tx_o, counter_word);

                if counter_idx = 0 then
                    assert unsigned(counter_word) > 0
                        report "perf_total_cycles deveria ser maior que zero."
                        severity warning;
                elsif counter_idx = 2 then
                    assert unsigned(counter_word) > 0
                        report "perf_compute_cycles deveria ser maior que zero."
                        severity warning;
                elsif counter_idx = 4 then
                    assert unsigned(counter_word) > 0
                        report "perf_num_tiles_processed deveria ser maior que zero."
                        severity warning;
                end if;
            end loop;
        end loop;

        report "SIM_RESULT: PASS - UART generico STREAM_A/STREAM_B/START/STREAM_C funcionando" severity note;
        finish;
    end process;

end architecture sim;
