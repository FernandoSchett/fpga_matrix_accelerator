library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_matrix_mult_4x4_top is
end entity tb_matrix_mult_4x4_top;

architecture sim of tb_matrix_mult_4x4_top is

    constant DATA_WIDTH : integer := 16;
    constant ACC_WIDTH  : integer := 32;
    constant CLK_PERIOD : time := 10 ns;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal wr_en      : std_logic := '0';
    signal matrix_sel : std_logic := '0';
    signal wr_addr    : unsigned(3 downto 0) := (others => '0');
    signal data_in    : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    signal start : std_logic := '0';
    signal busy  : std_logic;
    signal done  : std_logic;

    signal result_sel : unsigned(3 downto 0) := (others => '0');
    signal data_out   : signed(ACC_WIDTH-1 downto 0);

    procedure write_element(
        signal clk        : in std_logic;
        signal wr_en      : out std_logic;
        signal matrix_sel : out std_logic;
        signal wr_addr    : out unsigned(3 downto 0);
        signal data_in    : out signed(DATA_WIDTH-1 downto 0);
        constant sel      : in std_logic;
        constant addr     : in integer;
        constant value    : in integer
    ) is
    begin
        matrix_sel <= sel;
        wr_addr    <= to_unsigned(addr, 4);
        data_in    <= to_signed(value, DATA_WIDTH);
        wr_en      <= '1';

        wait until rising_edge(clk);

        wr_en <= '0';

        wait until rising_edge(clk);
    end procedure;

    procedure check_result(
        signal result_sel : out unsigned(3 downto 0);
        signal data_out   : in signed(ACC_WIDTH-1 downto 0);
        constant addr     : in integer;
        constant expected : in integer
    ) is
    begin
        result_sel <= to_unsigned(addr, 4);
        wait for 1 ns;

        assert data_out = to_signed(expected, ACC_WIDTH)
            report "Resultado incorreto no endereco " & integer'image(addr) &
                   ". Esperado " & integer'image(expected) &
                   ", obtido " & integer'image(to_integer(data_out))
            severity failure;
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.matrix_mult_4x4_top
        generic map (
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

            result_sel => result_sel,
            data_out   => data_out
        );

    stim_proc : process
    begin
        --------------------------------------------------------------------
        -- Reset inicial
        --------------------------------------------------------------------
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait for CLK_PERIOD;

        --------------------------------------------------------------------
        -- A =
        -- [ 1   2   3   4
        --   5   6   7   8
        --   9  10  11  12
        --  13  14  15  16 ]
        --------------------------------------------------------------------

        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 0,  1);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 1,  2);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 2,  3);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 3,  4);

        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 4,  5);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 5,  6);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 6,  7);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 7,  8);

        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 8,  9);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 9,  10);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 10, 11);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 11, 12);

        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 12, 13);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 13, 14);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 14, 15);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 15, 16);

        --------------------------------------------------------------------
        -- B =
        -- [ 1  0  2  1
        --   0  1  1  0
        --   3  0  0  2
        --   1  2  0  1 ]
        --------------------------------------------------------------------

        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 0,  1);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 1,  0);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 2,  2);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 3,  1);

        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 4,  0);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 5,  1);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 6,  1);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 7,  0);

        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 8,  3);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 9,  0);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 10, 0);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 11, 2);

        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 12, 1);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 13, 2);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 14, 0);
        write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 15, 1);

        --------------------------------------------------------------------
        -- Inicia cálculo
        --------------------------------------------------------------------

        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        wait until rising_edge(clk) and done = '1';
        wait until rising_edge(clk);

        --------------------------------------------------------------------
        -- C esperado =
        -- [14  10   4  11
        --  34  22  16  27
        --  54  34  28  43
        --  74  46  40  59]
        --------------------------------------------------------------------

        check_result(result_sel, data_out, 0,  14);
        check_result(result_sel, data_out, 1,  10);
        check_result(result_sel, data_out, 2,  4);
        check_result(result_sel, data_out, 3,  11);

        check_result(result_sel, data_out, 4,  34);
        check_result(result_sel, data_out, 5,  22);
        check_result(result_sel, data_out, 6,  16);
        check_result(result_sel, data_out, 7,  27);

        check_result(result_sel, data_out, 8,  54);
        check_result(result_sel, data_out, 9,  34);
        check_result(result_sel, data_out, 10, 28);
        check_result(result_sel, data_out, 11, 43);

        check_result(result_sel, data_out, 12, 74);
        check_result(result_sel, data_out, 13, 46);
        check_result(result_sel, data_out, 14, 40);
        check_result(result_sel, data_out, 15, 59);

        report "Teste 4x4 por blocos 2x2 passou." severity note;

        wait for 2 * CLK_PERIOD;

        report "Todos os testes passaram." severity note;
        report "SIM_RESULT: PASS" severity note;

        finish;
    end process;

end architecture sim;
