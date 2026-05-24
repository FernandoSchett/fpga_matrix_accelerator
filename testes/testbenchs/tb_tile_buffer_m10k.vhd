library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.matrix_tiled_pkg.all;

entity tb_tile_buffer_m10k is
end entity tb_tile_buffer_m10k;

architecture sim of tb_tile_buffer_m10k is

    constant CLK_PERIOD : time := 10 ns;
    constant DATA_WIDTH : positive := 8;
    constant ACC_WIDTH  : positive := 32;

    constant TILE2 : positive := 2;
    constant TILE4 : positive := 4;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal wr_en2 : std_logic := '0';
    signal row2   : unsigned(clog2(TILE2)-1 downto 0) := (others => '0');
    signal col2   : unsigned(clog2(TILE2)-1 downto 0) := (others => '0');
    signal wr_data2 : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal rd_data2 : signed(DATA_WIDTH-1 downto 0);
    signal addr2    : unsigned(clog2(TILE2*TILE2)-1 downto 0);

    signal wr_en4 : std_logic := '0';
    signal row4   : unsigned(clog2(TILE4)-1 downto 0) := (others => '0');
    signal col4   : unsigned(clog2(TILE4)-1 downto 0) := (others => '0');
    signal wr_data4 : signed(ACC_WIDTH-1 downto 0) := (others => '0');
    signal rd_data4 : signed(ACC_WIDTH-1 downto 0);
    signal addr4    : unsigned(clog2(TILE4*TILE4)-1 downto 0);

    function data_value(row_v : natural; col_v : natural; tile_size : positive) return integer is
    begin
        return 10 + (row_v * tile_size) + col_v;
    end function;

    function acc_value(row_v : natural; col_v : natural; tile_size : positive) return integer is
    begin
        return 1000 + (17 * row_v) + (3 * col_v) + tile_size;
    end function;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut_tile2_data : entity work.tile_buffer_m10k
        generic map (
            TILE_SIZE     => TILE2,
            DATA_WIDTH    => DATA_WIDTH,
            ACC_WIDTH     => ACC_WIDTH,
            USE_M10K      => true,
            IS_ACC_BUFFER => false,
            BUFFER_IMPL   => "INFERRED"
        )
        port map (
            clk            => clk,
            rst            => rst,
            wr_en          => wr_en2,
            local_row      => row2,
            local_col      => col2,
            wr_data        => wr_data2,
            rd_data        => rd_data2,
            local_addr_dbg => addr2
        );

    dut_tile4_acc : entity work.tile_buffer_m10k
        generic map (
            TILE_SIZE     => TILE4,
            DATA_WIDTH    => DATA_WIDTH,
            ACC_WIDTH     => ACC_WIDTH,
            USE_M10K      => true,
            IS_ACC_BUFFER => true,
            BUFFER_IMPL   => "INFERRED"
        )
        port map (
            clk            => clk,
            rst            => rst,
            wr_en          => wr_en4,
            local_row      => row4,
            local_col      => col4,
            wr_data        => wr_data4,
            rd_data        => rd_data4,
            local_addr_dbg => addr4
        );

    stim_proc : process
        variable expected_addr : natural;
        variable expected_data : integer;
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        for row_idx in 0 to TILE2-1 loop
            for col_idx in 0 to TILE2-1 loop
                expected_addr := (row_idx * TILE2) + col_idx;

                row2 <= to_unsigned(row_idx, row2'length);
                col2 <= to_unsigned(col_idx, col2'length);
                wr_data2 <= to_signed(data_value(row_idx, col_idx, TILE2), DATA_WIDTH);
                wr_en2 <= '1';
                wait for 1 ns;

                assert addr2 = to_unsigned(expected_addr, addr2'length)
                    report "Endereco local TILE_SIZE=2 incorreto na escrita."
                    severity failure;

                wait until rising_edge(clk);
                wr_en2 <= '0';
                wait until rising_edge(clk);
            end loop;
        end loop;

        for row_idx in 0 to TILE2-1 loop
            for col_idx in 0 to TILE2-1 loop
                expected_addr := (row_idx * TILE2) + col_idx;
                expected_data := data_value(row_idx, col_idx, TILE2);

                row2 <= to_unsigned(row_idx, row2'length);
                col2 <= to_unsigned(col_idx, col2'length);
                wait for 1 ns;

                assert addr2 = to_unsigned(expected_addr, addr2'length)
                    report "Endereco local TILE_SIZE=2 incorreto na leitura."
                    severity failure;

                wait until rising_edge(clk);
                wait for 1 ns;

                assert rd_data2 = to_signed(expected_data, DATA_WIDTH)
                    report "Dado incorreto no tile DATA_WIDTH TILE_SIZE=2."
                    severity failure;
            end loop;
        end loop;

        for row_idx in 0 to TILE4-1 loop
            for col_idx in 0 to TILE4-1 loop
                expected_addr := (row_idx * TILE4) + col_idx;

                row4 <= to_unsigned(row_idx, row4'length);
                col4 <= to_unsigned(col_idx, col4'length);
                wr_data4 <= to_signed(acc_value(row_idx, col_idx, TILE4), ACC_WIDTH);
                wr_en4 <= '1';
                wait for 1 ns;

                assert addr4 = to_unsigned(expected_addr, addr4'length)
                    report "Endereco local TILE_SIZE=4 incorreto na escrita."
                    severity failure;

                wait until rising_edge(clk);
                wr_en4 <= '0';
                wait until rising_edge(clk);
            end loop;
        end loop;

        for row_idx in 0 to TILE4-1 loop
            for col_idx in 0 to TILE4-1 loop
                expected_addr := (row_idx * TILE4) + col_idx;
                expected_data := acc_value(row_idx, col_idx, TILE4);

                row4 <= to_unsigned(row_idx, row4'length);
                col4 <= to_unsigned(col_idx, col4'length);
                wait for 1 ns;

                assert addr4 = to_unsigned(expected_addr, addr4'length)
                    report "Endereco local TILE_SIZE=4 incorreto na leitura."
                    severity failure;

                wait until rising_edge(clk);
                wait for 1 ns;

                assert rd_data4 = to_signed(expected_data, ACC_WIDTH)
                    report "Dado incorreto no tile ACC_WIDTH TILE_SIZE=4."
                    severity failure;
            end loop;
        end loop;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
