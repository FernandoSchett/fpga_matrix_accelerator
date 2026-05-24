library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tile_compute_engine is
end entity tb_tile_compute_engine;

architecture sim of tb_tile_compute_engine is

    constant CLK_PERIOD : time := 10 ns;
    constant DATA_WIDTH : positive := 8;
    constant ACC_WIDTH  : positive := 32;

    constant TILE2 : positive := 2;
    constant TILE4 : positive := 4;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal start_t2_m1 : std_logic := '0';
    signal done_t2_m1  : std_logic;
    signal a_t2_m1     : std_logic_vector((TILE2*TILE2*DATA_WIDTH)-1 downto 0) := (others => '0');
    signal b_t2_m1     : std_logic_vector((TILE2*TILE2*DATA_WIDTH)-1 downto 0) := (others => '0');
    signal c_in_t2_m1  : std_logic_vector((TILE2*TILE2*ACC_WIDTH)-1 downto 0) := (others => '0');
    signal c_out_t2_m1 : std_logic_vector((TILE2*TILE2*ACC_WIDTH)-1 downto 0);

    signal start_t2_m2 : std_logic := '0';
    signal done_t2_m2  : std_logic;
    signal a_t2_m2     : std_logic_vector((TILE2*TILE2*DATA_WIDTH)-1 downto 0) := (others => '0');
    signal b_t2_m2     : std_logic_vector((TILE2*TILE2*DATA_WIDTH)-1 downto 0) := (others => '0');
    signal c_in_t2_m2  : std_logic_vector((TILE2*TILE2*ACC_WIDTH)-1 downto 0) := (others => '0');
    signal c_out_t2_m2 : std_logic_vector((TILE2*TILE2*ACC_WIDTH)-1 downto 0);

    signal start_t4_m4 : std_logic := '0';
    signal done_t4_m4  : std_logic;
    signal a_t4_m4     : std_logic_vector((TILE4*TILE4*DATA_WIDTH)-1 downto 0) := (others => '0');
    signal b_t4_m4     : std_logic_vector((TILE4*TILE4*DATA_WIDTH)-1 downto 0) := (others => '0');
    signal c_in_t4_m4  : std_logic_vector((TILE4*TILE4*ACC_WIDTH)-1 downto 0) := (others => '0');
    signal c_out_t4_m4 : std_logic_vector((TILE4*TILE4*ACC_WIDTH)-1 downto 0);

    function a_value(row_idx : natural; col_idx : natural; tile_size : positive) return integer is
    begin
        return ((row_idx + (2 * col_idx) + tile_size) mod 8) - 3;
    end function;

    function b_value(row_idx : natural; col_idx : natural; tile_size : positive) return integer is
    begin
        return (((3 * row_idx) - col_idx + tile_size + 5) mod 8) - 2;
    end function;

    function c_seed(row_idx : natural; col_idx : natural; tile_size : positive) return integer is
    begin
        return 100 + (tile_size * 10) + (row_idx * tile_size) + col_idx;
    end function;

    function expected_value(row_idx : natural; col_idx : natural; tile_size : positive) return integer is
        variable acc : integer;
    begin
        acc := c_seed(row_idx, col_idx, tile_size);

        for k in 0 to tile_size-1 loop
            acc := acc + (a_value(row_idx, k, tile_size) * b_value(k, col_idx, tile_size));
        end loop;

        return acc;
    end function;

    function pack_data_tile(
        constant tile_size  : positive;
        constant data_width : positive;
        constant matrix_sel : natural
    ) return std_logic_vector is
        variable result : std_logic_vector((tile_size*tile_size*data_width)-1 downto 0);
        variable idx    : natural;
        variable left_i : natural;
        variable value  : integer;
    begin
        for row_idx in 0 to tile_size-1 loop
            for col_idx in 0 to tile_size-1 loop
                idx    := (row_idx * tile_size) + col_idx;
                left_i := ((idx + 1) * data_width) - 1;

                if matrix_sel = 0 then
                    value := a_value(row_idx, col_idx, tile_size);
                else
                    value := b_value(row_idx, col_idx, tile_size);
                end if;

                result(left_i downto left_i - data_width + 1) :=
                    std_logic_vector(to_signed(value, data_width));
            end loop;
        end loop;

        return result;
    end function;

    function pack_c_tile(
        constant tile_size : positive;
        constant acc_width : positive
    ) return std_logic_vector is
        variable result : std_logic_vector((tile_size*tile_size*acc_width)-1 downto 0);
        variable idx    : natural;
        variable left_i : natural;
    begin
        for row_idx in 0 to tile_size-1 loop
            for col_idx in 0 to tile_size-1 loop
                idx    := (row_idx * tile_size) + col_idx;
                left_i := ((idx + 1) * acc_width) - 1;
                result(left_i downto left_i - acc_width + 1) :=
                    std_logic_vector(to_signed(c_seed(row_idx, col_idx, tile_size), acc_width));
            end loop;
        end loop;

        return result;
    end function;

    function get_acc(
        constant flat      : std_logic_vector;
        constant idx       : natural;
        constant acc_width : positive
    ) return integer is
        variable left_i : natural;
    begin
        left_i := ((idx + 1) * acc_width) - 1;
        return to_integer(signed(flat(left_i downto left_i - acc_width + 1)));
    end function;

    procedure run_case(
        signal clk        : in std_logic;
        signal start      : out std_logic;
        signal done       : in std_logic;
        signal a_tile     : out std_logic_vector;
        signal b_tile     : out std_logic_vector;
        signal c_tile_in  : out std_logic_vector;
        signal c_tile_out : in std_logic_vector;
        constant tile_size  : in positive;
        constant num_macs   : in positive;
        constant data_width : in positive;
        constant acc_width  : in positive;
        constant label_s    : in string;
        variable cycles_out : out natural
    ) is
        variable idx      : natural;
        variable expected : integer;
        variable observed : integer;
    begin
        a_tile    <= pack_data_tile(tile_size, data_width, 0);
        b_tile    <= pack_data_tile(tile_size, data_width, 1);
        c_tile_in <= pack_c_tile(tile_size, acc_width);

        wait until rising_edge(clk);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        cycles_out := 0;

        loop
            wait until rising_edge(clk);
            cycles_out := cycles_out + 1;

            assert cycles_out < 1000
                report "Timeout no compute " & label_s
                severity failure;

            exit when done = '1';
        end loop;

        report "Ciclos de compute " & label_s & ": " & integer'image(cycles_out) severity note;

        wait for 1 ns;

        for row_idx in 0 to tile_size-1 loop
            for col_idx in 0 to tile_size-1 loop
                idx      := (row_idx * tile_size) + col_idx;
                expected := expected_value(row_idx, col_idx, tile_size);
                observed := get_acc(c_tile_out, idx, acc_width);

                assert observed = expected
                    report "Resultado incorreto em " & label_s &
                           " idx=" & integer'image(idx) &
                           ". Esperado " & integer'image(expected) &
                           ", obtido " & integer'image(observed)
                    severity failure;
            end loop;
        end loop;
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut_t2_m1 : entity work.matrix_tiled_compute_core
        generic map (
            TILE_SIZE  => TILE2,
            NUM_MACS   => 1,
            DATA_WIDTH => DATA_WIDTH,
            ACC_WIDTH  => ACC_WIDTH
        )
        port map (
            clk        => clk,
            rst        => rst,
            start      => start_t2_m1,
            done       => done_t2_m1,
            a_tile     => a_t2_m1,
            b_tile     => b_t2_m1,
            c_tile_in  => c_in_t2_m1,
            c_tile_out => c_out_t2_m1
        );

    dut_t2_m2 : entity work.matrix_tiled_compute_core
        generic map (
            TILE_SIZE  => TILE2,
            NUM_MACS   => 2,
            DATA_WIDTH => DATA_WIDTH,
            ACC_WIDTH  => ACC_WIDTH
        )
        port map (
            clk        => clk,
            rst        => rst,
            start      => start_t2_m2,
            done       => done_t2_m2,
            a_tile     => a_t2_m2,
            b_tile     => b_t2_m2,
            c_tile_in  => c_in_t2_m2,
            c_tile_out => c_out_t2_m2
        );

    dut_t4_m4 : entity work.matrix_tiled_compute_core
        generic map (
            TILE_SIZE  => TILE4,
            NUM_MACS   => 4,
            DATA_WIDTH => DATA_WIDTH,
            ACC_WIDTH  => ACC_WIDTH
        )
        port map (
            clk        => clk,
            rst        => rst,
            start      => start_t4_m4,
            done       => done_t4_m4,
            a_tile     => a_t4_m4,
            b_tile     => b_t4_m4,
            c_tile_in  => c_in_t4_m4,
            c_tile_out => c_out_t4_m4
        );

    stim_proc : process
        variable cycles_t2_m1 : natural := 0;
        variable cycles_t2_m2 : natural := 0;
        variable cycles_t4_m4 : natural := 0;
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        run_case(clk, start_t2_m1, done_t2_m1, a_t2_m1, b_t2_m1,
                 c_in_t2_m1, c_out_t2_m1, TILE2, 1, DATA_WIDTH, ACC_WIDTH,
                 "TILE_SIZE=2 NUM_MACS=1", cycles_t2_m1);

        run_case(clk, start_t2_m2, done_t2_m2, a_t2_m2, b_t2_m2,
                 c_in_t2_m2, c_out_t2_m2, TILE2, 2, DATA_WIDTH, ACC_WIDTH,
                 "TILE_SIZE=2 NUM_MACS=2", cycles_t2_m2);

        assert cycles_t2_m2 < cycles_t2_m1
            report "NUM_MACS=2 nao reduziu ciclos em relacao a NUM_MACS=1."
            severity failure;

        run_case(clk, start_t4_m4, done_t4_m4, a_t4_m4, b_t4_m4,
                 c_in_t4_m4, c_out_t4_m4, TILE4, 4, DATA_WIDTH, ACC_WIDTH,
                 "TILE_SIZE=4 NUM_MACS=4", cycles_t4_m4);

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
