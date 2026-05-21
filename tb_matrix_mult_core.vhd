library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_matrix_mult_top is
    generic (
        DATA_WIDTH : positive := 16;
        ACC_WIDTH  : positive := 32;
        NUM_TESTS  : positive := 1;
        ROWS_A     : positive := 2;
        COLS_A     : positive := 2;
        ROWS_B     : positive := 2;
        COLS_B     : positive := 2;
        INPUT_FILE  : string := "matrix_inputs.txt";
        OUTPUT_FILE : string := "matrix_outputs.txt"
    );
end entity tb_matrix_mult_top;

architecture sim of tb_matrix_mult_top is

    constant CLK_PERIOD : time := 10 ns;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal wr_en      : std_logic := '0';
    signal matrix_sel : std_logic := '0';
    signal wr_addr    : unsigned(1 downto 0) := (others => '0');
    signal data_in    : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    signal start : std_logic := '0';
    signal busy  : std_logic;
    signal done  : std_logic;

    signal result_sel : unsigned(1 downto 0) := (others => '0');
    signal data_out   : signed(ACC_WIDTH-1 downto 0);

    function is_blank_or_comment(s : string) return boolean is
    begin
        for i in s'range loop
            if s(i) = '#' then
                return true;
            elsif s(i) /= ' ' then
                return false;
            end if;
        end loop;

        return true;
    end function;

    procedure next_data_line(
        file f      : text;
        variable l  : inout line;
        variable ok : out boolean
    ) is
    begin
        ok := false;

        while not endfile(f) loop
            readline(f, l);

            if not is_blank_or_comment(l.all) then
                ok := true;
                return;
            end if;
        end loop;
    end procedure;

    procedure write_element(
        signal clk        : in std_logic;
        signal wr_en      : out std_logic;
        signal matrix_sel : out std_logic;
        signal wr_addr    : out unsigned(1 downto 0);
        signal data_in    : out signed(DATA_WIDTH-1 downto 0);
        constant sel      : in std_logic;
        constant addr     : in integer;
        constant value    : in integer
    ) is
    begin
        matrix_sel <= sel;
        wr_addr    <= to_unsigned(addr, 2);
        data_in    <= to_signed(value, DATA_WIDTH);
        wr_en      <= '1';

        wait until rising_edge(clk);

        wr_en <= '0';

        wait until rising_edge(clk);
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.matrix_mult_top
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
        file input_vectors  : text;
        file output_vectors : text;

        variable in_line  : line;
        variable out_line : line;
        variable ok_in    : boolean;
        variable ok_out   : boolean;

        variable va00 : integer;
        variable va01 : integer;
        variable va10 : integer;
        variable va11 : integer;

        variable vb00 : integer;
        variable vb01 : integer;
        variable vb10 : integer;
        variable vb11 : integer;

        variable exp_c00 : integer;
        variable exp_c01 : integer;
        variable exp_c10 : integer;
        variable exp_c11 : integer;

        variable test_id : integer := 0;
    begin
        assert ROWS_A = 2 and COLS_A = 2 and ROWS_B = 2 and COLS_B = 2
            report "Este testbench/DUT ainda suporta somente A 2x2 e B 2x2. Ajuste ROWS_A, COLS_A, ROWS_B e COLS_B no .env."
            severity failure;

        file_open(input_vectors, INPUT_FILE, read_mode);
        file_open(output_vectors, OUTPUT_FILE, read_mode);

        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait for CLK_PERIOD;

        next_data_line(input_vectors, in_line, ok_in);
        assert ok_in report "Arquivo matrix_inputs.txt vazio ou invalido." severity failure;

        next_data_line(output_vectors, out_line, ok_out);
        assert ok_out report "Arquivo matrix_outputs.txt vazio ou invalido." severity failure;

        while true loop
            next_data_line(input_vectors, in_line, ok_in);

            if not ok_in then
                exit;
            end if;

            next_data_line(input_vectors, in_line, ok_in);
            assert ok_in report "Esperado bloco A no arquivo de entrada." severity failure;

            next_data_line(input_vectors, in_line, ok_in);
            assert ok_in report "Esperada primeira linha da matriz A." severity failure;
            read(in_line, va00);
            read(in_line, va01);

            next_data_line(input_vectors, in_line, ok_in);
            assert ok_in report "Esperada segunda linha da matriz A." severity failure;
            read(in_line, va10);
            read(in_line, va11);

            next_data_line(input_vectors, in_line, ok_in);
            assert ok_in report "Esperado bloco B no arquivo de entrada." severity failure;

            next_data_line(input_vectors, in_line, ok_in);
            assert ok_in report "Esperada primeira linha da matriz B." severity failure;
            read(in_line, vb00);
            read(in_line, vb01);

            next_data_line(input_vectors, in_line, ok_in);
            assert ok_in report "Esperada segunda linha da matriz B." severity failure;
            read(in_line, vb10);
            read(in_line, vb11);

            next_data_line(input_vectors, in_line, ok_in);
            assert ok_in report "Esperado END_TEST no arquivo de entrada." severity failure;

            next_data_line(output_vectors, out_line, ok_out);
            assert ok_out report "Esperado TEST no arquivo de saida." severity failure;

            next_data_line(output_vectors, out_line, ok_out);
            assert ok_out report "Esperado bloco C no arquivo de saida." severity failure;

            next_data_line(output_vectors, out_line, ok_out);
            assert ok_out report "Esperada primeira linha da matriz C." severity failure;
            read(out_line, exp_c00);
            read(out_line, exp_c01);

            next_data_line(output_vectors, out_line, ok_out);
            assert ok_out report "Esperada segunda linha da matriz C." severity failure;
            read(out_line, exp_c10);
            read(out_line, exp_c11);

            next_data_line(output_vectors, out_line, ok_out);
            assert ok_out report "Esperado END_TEST no arquivo de saida." severity failure;

            write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 0, va00);
            write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 1, va01);
            write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 2, va10);
            write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '0', 3, va11);

            write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 0, vb00);
            write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 1, vb01);
            write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 2, vb10);
            write_element(clk, wr_en, matrix_sel, wr_addr, data_in, '1', 3, vb11);

            start <= '1';
            wait until rising_edge(clk);
            start <= '0';

            wait until rising_edge(clk) and done = '1';
            wait until rising_edge(clk);

            result_sel <= to_unsigned(0, 2);
            wait for 1 ns;
            assert data_out = to_signed(exp_c00, ACC_WIDTH)
                report "Teste " & integer'image(test_id) & " falhou: C00 incorreto. Esperado "
                & integer'image(exp_c00) & ", obtido " & integer'image(to_integer(data_out))
                severity failure;

            result_sel <= to_unsigned(1, 2);
            wait for 1 ns;
            assert data_out = to_signed(exp_c01, ACC_WIDTH)
                report "Teste " & integer'image(test_id) & " falhou: C01 incorreto. Esperado "
                & integer'image(exp_c01) & ", obtido " & integer'image(to_integer(data_out))
                severity failure;

            result_sel <= to_unsigned(2, 2);
            wait for 1 ns;
            assert data_out = to_signed(exp_c10, ACC_WIDTH)
                report "Teste " & integer'image(test_id) & " falhou: C10 incorreto. Esperado "
                & integer'image(exp_c10) & ", obtido " & integer'image(to_integer(data_out))
                severity failure;

            result_sel <= to_unsigned(3, 2);
            wait for 1 ns;
            assert data_out = to_signed(exp_c11, ACC_WIDTH)
                report "Teste " & integer'image(test_id) & " falhou: C11 incorreto. Esperado "
                & integer'image(exp_c11) & ", obtido " & integer'image(to_integer(data_out))
                severity failure;

            report "Teste " & integer'image(test_id) & " passou." severity note;

            test_id := test_id + 1;

            wait for 2 * CLK_PERIOD;
        end loop;

        next_data_line(output_vectors, out_line, ok_out);
        assert not ok_out report "matrix_outputs.txt possui testes extras." severity failure;
        assert test_id = NUM_TESTS
            report "Quantidade de testes executados diferente de NUM_TESTS. Esperado "
            & integer'image(NUM_TESTS) & ", executado " & integer'image(test_id)
            severity failure;

        report "Todos os testes passaram. Total de testes: " & integer'image(test_id) severity note;
        report "SIM_RESULT: PASS" severity note;

        file_close(input_vectors);
        file_close(output_vectors);

        finish;
    end process;

end architecture sim;
