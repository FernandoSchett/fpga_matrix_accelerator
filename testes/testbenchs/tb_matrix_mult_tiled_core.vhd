library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.matrix_tiled_pkg.all;

entity tb_matrix_mult_tiled_core is
    generic (
        N          : positive := 4;
        TILE_SIZE  : positive := 2;
        NUM_MACS   : positive := 2;
        DATA_WIDTH : positive := 8;
        ACC_WIDTH  : positive := 32
    );
end entity tb_matrix_mult_tiled_core;

architecture sim of tb_matrix_mult_tiled_core is

    constant CLK_PERIOD  : time := 10 ns;
    constant ADDR_WIDTH  : positive := clog2(N*N);
    constant MATRIX_SIZE : positive := N * N;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal wr_en      : std_logic := '0';
    signal matrix_sel : std_logic := '0';
    signal wr_addr    : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal data_in    : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    signal start : std_logic := '0';
    signal busy  : std_logic;
    signal done  : std_logic;

    signal result_addr : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal data_out    : signed(ACC_WIDTH-1 downto 0);

    function a_value(row_idx : natural; col_idx : natural) return integer is
    begin
        return (row_idx + (2 * col_idx) + 1) mod 8;
    end function;

    function b_value(row_idx : natural; col_idx : natural) return integer is
    begin
        return ((3 * row_idx) + col_idx + 2) mod 8;
    end function;

    function c_expected(row_idx : natural; col_idx : natural) return integer is
        variable acc : integer := 0;
    begin
        for k in 0 to N-1 loop
            acc := acc + a_value(row_idx, k) * b_value(k, col_idx);
        end loop;

        return acc;
    end function;

    procedure write_element(
        signal clk        : in std_logic;
        signal wr_en      : out std_logic;
        signal matrix_sel : out std_logic;
        signal wr_addr    : out unsigned(ADDR_WIDTH-1 downto 0);
        signal data_in    : out signed(DATA_WIDTH-1 downto 0);
        constant sel      : in std_logic;
        constant addr     : in natural;
        constant value    : in integer
    ) is
    begin
        matrix_sel <= sel;
        wr_addr    <= to_unsigned(addr, ADDR_WIDTH);
        data_in    <= to_signed(value, DATA_WIDTH);
        wr_en      <= '1';

        wait until rising_edge(clk);

        wr_en <= '0';

        wait until rising_edge(clk);
    end procedure;

    procedure check_result(
        signal clk         : in std_logic;
        signal result_addr : out unsigned(ADDR_WIDTH-1 downto 0);
        signal data_out    : in signed(ACC_WIDTH-1 downto 0);
        constant addr      : in natural;
        constant expected  : in integer
    ) is
    begin
        result_addr <= to_unsigned(addr, ADDR_WIDTH);

        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;

        assert data_out = to_signed(expected, ACC_WIDTH)
            report "Resultado incorreto no endereco " & integer'image(addr) &
                   ". Esperado " & integer'image(expected) &
                   ", obtido " & integer'image(to_integer(data_out))
            severity failure;
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.matrix_mult_tiled_core
        generic map (
            N          => N,
            TILE_SIZE  => TILE_SIZE,
            NUM_MACS   => NUM_MACS,
            DATA_WIDTH => DATA_WIDTH,
            ACC_WIDTH  => ACC_WIDTH
        )
        port map (
            clk => clk,
            rst => rst,

            wr_en      => wr_en,
            matrix_sel => matrix_sel,
            wr_addr    => wr_addr,
            data_in    => data_in,

            start => start,
            busy  => busy,
            done  => done,

            result_addr => result_addr,
            data_out    => data_out
        );

    stim_proc : process
        variable addr        : natural;
        variable exec_cycles : natural := 0;
    begin
        assert N mod TILE_SIZE = 0
            report "N precisa ser multiplo de TILE_SIZE para este testbench."
            severity failure;

        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait for CLK_PERIOD;

        for row_idx in 0 to N-1 loop
            for col_idx in 0 to N-1 loop
                addr := row_idx * N + col_idx;
                write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', addr, a_value(row_idx, col_idx));
            end loop;
        end loop;

        for row_idx in 0 to N-1 loop
            for col_idx in 0 to N-1 loop
                addr := row_idx * N + col_idx;
                write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', addr, b_value(row_idx, col_idx));
            end loop;
        end loop;

        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        exec_cycles := 0;

        loop
            wait until rising_edge(clk);
            exec_cycles := exec_cycles + 1;

            if done = '1' then
                exit;
            end if;
        end loop;

        report "Ciclos de execucao: " & integer'image(exec_cycles) severity note;

        wait until rising_edge(clk);

        for row_idx in 0 to N-1 loop
            for col_idx in 0 to N-1 loop
                addr := row_idx * N + col_idx;
                check_result(clk, result_addr, data_out, addr, c_expected(row_idx, col_idx));
            end loop;
        end loop;

        report "Teste tiled passou para N=" & integer'image(N) &
               ", TILE_SIZE=" & integer'image(TILE_SIZE) &
               ", NUM_MACS=" & integer'image(NUM_MACS) severity note;
        report "SIM_RESULT: PASS" severity note;

        finish;
    end process;

end architecture sim;
