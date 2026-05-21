library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_matrix_mult_core is
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
end entity tb_matrix_mult_core;

architecture sim of tb_matrix_mult_core is

    constant CLK_PERIOD : time := 10 ns;

    signal clk   : std_logic := '0';
    signal rst   : std_logic := '0';
    signal start : std_logic := '0';
    signal done  : std_logic;

    signal a00 : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal a01 : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal a10 : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal a11 : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    signal b00 : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal b01 : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal b10 : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal b11 : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    signal c00 : signed(ACC_WIDTH-1 downto 0);
    signal c01 : signed(ACC_WIDTH-1 downto 0);
    signal c10 : signed(ACC_WIDTH-1 downto 0);
    signal c11 : signed(ACC_WIDTH-1 downto 0);

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

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.matrix_mult_core
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            ACC_WIDTH  => ACC_WIDTH
        )
        port map (
            clk   => clk,
            rst   => rst,
            start => start,
            done  => done,

            a00 => a00,
            a01 => a01,
            a10 => a10,
            a11 => a11,

            b00 => b00,
            b01 => b01,
            b10 => b10,
            b11 => b11,

            c00 => c00,
            c01 => c01,
            c10 => c10,
            c11 => c11
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
        assert ok_out report "Arquivo matrix_output.txt vazio ou invalido." severity failure;

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

            a00 <= to_signed(va00, DATA_WIDTH);
            a01 <= to_signed(va01, DATA_WIDTH);
            a10 <= to_signed(va10, DATA_WIDTH);
            a11 <= to_signed(va11, DATA_WIDTH);

            b00 <= to_signed(vb00, DATA_WIDTH);
            b01 <= to_signed(vb01, DATA_WIDTH);
            b10 <= to_signed(vb10, DATA_WIDTH);
            b11 <= to_signed(vb11, DATA_WIDTH);

            wait until rising_edge(clk);

            start <= '1';
            wait until rising_edge(clk);
            start <= '0';

            wait until rising_edge(clk) and done = '1';
            wait until rising_edge(clk);

            assert c00 = to_signed(exp_c00, ACC_WIDTH)
                report "Teste " & integer'image(test_id) & " falhou: C00 incorreto. Esperado "
                & integer'image(exp_c00) & ", obtido " & integer'image(to_integer(c00))
                severity failure;

            assert c01 = to_signed(exp_c01, ACC_WIDTH)
                report "Teste " & integer'image(test_id) & " falhou: C01 incorreto. Esperado "
                & integer'image(exp_c01) & ", obtido " & integer'image(to_integer(c01))
                severity failure;

            assert c10 = to_signed(exp_c10, ACC_WIDTH)
                report "Teste " & integer'image(test_id) & " falhou: C10 incorreto. Esperado "
                & integer'image(exp_c10) & ", obtido " & integer'image(to_integer(c10))
                severity failure;

            assert c11 = to_signed(exp_c11, ACC_WIDTH)
                report "Teste " & integer'image(test_id) & " falhou: C11 incorreto. Esperado "
                & integer'image(exp_c11) & ", obtido " & integer'image(to_integer(c11))
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
