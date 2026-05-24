library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.matrix_accel_config_pkg.all;

entity tb_matrix_accelerator_sdram_core_top is
end entity tb_matrix_accelerator_sdram_core_top;

architecture sim of tb_matrix_accelerator_sdram_core_top is

    constant CLK_PERIOD       : time := 10 ns;
    constant TILE_SIZE        : positive := 2;
    constant NUM_MACS         : positive := 2;
    constant DATA_WIDTH       : positive := 8;
    constant ACC_WIDTH        : positive := 32;
    constant SDRAM_DATA_WIDTH : positive := 32;
    constant SDRAM_ADDR_WIDTH : positive := 10;

    constant N4          : positive := 4;
    constant N8          : positive := 8;
    constant SDRAM_DEPTH : positive := 1024;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal host_wr_en4      : std_logic := '0';
    signal host_matrix_sel4 : std_logic_vector(1 downto 0) := MATRIX_ID_A;
    signal host_addr4       : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal host_data_in4    : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0) := (others => '0');
    signal host_rd_en4      : std_logic := '0';
    signal host_rd_addr4    : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal host_data_out4   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal start4           : std_logic := '0';
    signal busy4            : std_logic;
    signal done4            : std_logic;

    signal host_wr_en8      : std_logic := '0';
    signal host_matrix_sel8 : std_logic_vector(1 downto 0) := MATRIX_ID_A;
    signal host_addr8       : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal host_data_in8    : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0) := (others => '0');
    signal host_rd_en8      : std_logic := '0';
    signal host_rd_addr8    : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal host_data_out8   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal start8           : std_logic := '0';
    signal busy8            : std_logic;
    signal done8            : std_logic;

    function a_value(
        constant row_idx : natural;
        constant col_idx : natural
    ) return integer is
    begin
        return (row_idx + (2 * col_idx) + 1) mod 8;
    end function;

    function b_value(
        constant row_idx : natural;
        constant col_idx : natural
    ) return integer is
    begin
        return ((3 * row_idx) + col_idx + 2) mod 8;
    end function;

    function c_expected(
        constant n_value : positive;
        constant row_idx : natural;
        constant col_idx : natural
    ) return integer is
        variable acc : integer := 0;
    begin
        for k_idx in 0 to n_value-1 loop
            acc := acc + a_value(row_idx, k_idx) * b_value(k_idx, col_idx);
        end loop;

        return acc;
    end function;

    procedure host_write(
        signal wr_en      : out std_logic;
        signal matrix_sel : out std_logic_vector(1 downto 0);
        signal addr_sig   : out unsigned;
        signal data_sig   : out std_logic_vector;
        constant sel      : std_logic_vector(1 downto 0);
        constant addr_nat : natural;
        constant value    : integer
    ) is
    begin
        matrix_sel <= sel;
        addr_sig   <= to_unsigned(addr_nat, addr_sig'length);
        data_sig   <= std_logic_vector(to_signed(value, data_sig'length));
        wr_en      <= '1';
        wait until rising_edge(clk);
        wr_en <= '0';

        for cycle_idx in 0 to 3 loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

    procedure host_read_c(
        signal rd_en      : out std_logic;
        signal rd_addr    : out unsigned;
        signal data_sig   : in std_logic_vector;
        constant addr_nat : natural;
        variable value    : out integer
    ) is
    begin
        rd_addr <= to_unsigned(addr_nat, rd_addr'length);
        rd_en   <= '1';
        wait until rising_edge(clk);
        rd_en <= '0';

        for cycle_idx in 0 to 5 loop
            wait until rising_edge(clk);
        end loop;

        value := to_integer(signed(data_sig));
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut_n4 : entity work.matrix_accelerator_sdram_core_top
        generic map (
            N                => N4,
            TILE_SIZE        => TILE_SIZE,
            NUM_MACS         => NUM_MACS,
            DATA_WIDTH       => DATA_WIDTH,
            ACC_WIDTH        => ACC_WIDTH,
            SDRAM_DATA_WIDTH => SDRAM_DATA_WIDTH,
            SDRAM_ADDR_WIDTH => SDRAM_ADDR_WIDTH,
            SDRAM_DEPTH      => SDRAM_DEPTH,
            READ_LATENCY     => 1,
            WRITE_LATENCY    => 1
        )
        port map (
            clk             => clk,
            rst             => rst,
            host_wr_en      => host_wr_en4,
            host_matrix_sel => host_matrix_sel4,
            host_addr       => host_addr4,
            host_data_in    => host_data_in4,
            host_rd_en      => host_rd_en4,
            host_rd_addr    => host_rd_addr4,
            host_data_out   => host_data_out4,
            start           => start4,
            busy            => busy4,
            done            => done4,
            perf_total_cycles        => open,
            perf_load_cycles         => open,
            perf_compute_cycles      => open,
            perf_store_cycles        => open,
            perf_num_tiles_processed => open,
            perf_num_mac_ops_issued  => open,
            load_active              => open,
            compute_active           => open,
            store_active             => open,
            tile_done                => open
        );

    dut_n8 : entity work.matrix_accelerator_sdram_core_top
        generic map (
            N                => N8,
            TILE_SIZE        => TILE_SIZE,
            NUM_MACS         => NUM_MACS,
            DATA_WIDTH       => DATA_WIDTH,
            ACC_WIDTH        => ACC_WIDTH,
            SDRAM_DATA_WIDTH => SDRAM_DATA_WIDTH,
            SDRAM_ADDR_WIDTH => SDRAM_ADDR_WIDTH,
            SDRAM_DEPTH      => SDRAM_DEPTH,
            READ_LATENCY     => 1,
            WRITE_LATENCY    => 1
        )
        port map (
            clk             => clk,
            rst             => rst,
            host_wr_en      => host_wr_en8,
            host_matrix_sel => host_matrix_sel8,
            host_addr       => host_addr8,
            host_data_in    => host_data_in8,
            host_rd_en      => host_rd_en8,
            host_rd_addr    => host_rd_addr8,
            host_data_out   => host_data_out8,
            start           => start8,
            busy            => busy8,
            done            => done8,
            perf_total_cycles        => open,
            perf_load_cycles         => open,
            perf_compute_cycles      => open,
            perf_store_cycles        => open,
            perf_num_tiles_processed => open,
            perf_num_mac_ops_issued  => open,
            load_active              => open,
            compute_active           => open,
            store_active             => open,
            tile_done                => open
        );

    stim_proc : process
        variable addr        : natural;
        variable exec_cycles : natural;
        variable got_value   : integer;
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        for row_idx in 0 to N4-1 loop
            for col_idx in 0 to N4-1 loop
                addr := row_idx * N4 + col_idx;

                host_write(host_wr_en4, host_matrix_sel4, host_addr4, host_data_in4,
                           MATRIX_ID_A, addr, a_value(row_idx, col_idx));
                host_write(host_wr_en4, host_matrix_sel4, host_addr4, host_data_in4,
                           MATRIX_ID_B, addr, b_value(row_idx, col_idx));
            end loop;
        end loop;

        start4 <= '1';
        wait until rising_edge(clk);
        start4 <= '0';

        exec_cycles := 0;
        for cycle_idx in 0 to 5000 loop
            wait until rising_edge(clk);
            exec_cycles := exec_cycles + 1;
            exit when done4 = '1';
        end loop;

        assert done4 = '1'
            report "matrix_accelerator_sdram_core_top N=4 nao finalizou."
            severity failure;

        report "Ciclos de execucao: " & integer'image(exec_cycles) severity note;

        for row_idx in 0 to N4-1 loop
            for col_idx in 0 to N4-1 loop
                addr := row_idx * N4 + col_idx;
                host_read_c(host_rd_en4, host_rd_addr4, host_data_out4, addr, got_value);

                assert got_value = c_expected(N4, row_idx, col_idx)
                    report "Resultado incorreto no core top SDRAM N=4."
                    severity failure;
            end loop;
        end loop;

        for row_idx in 0 to N8-1 loop
            for col_idx in 0 to N8-1 loop
                addr := row_idx * N8 + col_idx;

                host_write(host_wr_en8, host_matrix_sel8, host_addr8, host_data_in8,
                           MATRIX_ID_A, addr, a_value(row_idx, col_idx));
                host_write(host_wr_en8, host_matrix_sel8, host_addr8, host_data_in8,
                           MATRIX_ID_B, addr, b_value(row_idx, col_idx));
            end loop;
        end loop;

        start8 <= '1';
        wait until rising_edge(clk);
        start8 <= '0';

        exec_cycles := 0;
        for cycle_idx in 0 to 30000 loop
            wait until rising_edge(clk);
            exec_cycles := exec_cycles + 1;
            exit when done8 = '1';
        end loop;

        assert done8 = '1'
            report "matrix_accelerator_sdram_core_top N=8 nao finalizou."
            severity failure;

        report "Ciclos de execucao: " & integer'image(exec_cycles) severity note;

        for row_idx in 0 to N8-1 loop
            for col_idx in 0 to N8-1 loop
                addr := row_idx * N8 + col_idx;
                host_read_c(host_rd_en8, host_rd_addr8, host_data_out8, addr, got_value);

                assert got_value = c_expected(N8, row_idx, col_idx)
                    report "Resultado incorreto no core top SDRAM N=8."
                    severity failure;
            end loop;
        end loop;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
