library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tile_buffer_m10k is
end entity tb_tile_buffer_m10k;

architecture sim of tb_tile_buffer_m10k is

    constant CLK_PERIOD : time := 10 ns;
    constant WIDTH      : positive := 8;
    constant ADDR_WIDTH : positive := 4;

    signal clk     : std_logic := '0';
    signal wr_en   : std_logic := '0';
    signal addr    : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal wr_data : signed(WIDTH-1 downto 0) := (others => '0');
    signal rd_data : signed(WIDTH-1 downto 0);

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.tile_buffer_m10k
        generic map (
            ELEMENT_WIDTH => WIDTH,
            ADDR_WIDTH    => ADDR_WIDTH,
            DEPTH         => 16
        )
        port map (
            clk     => clk,
            wr_en   => wr_en,
            addr    => addr,
            wr_data => wr_data,
            rd_data => rd_data
        );

    stim_proc : process
    begin
        wait until rising_edge(clk);
        addr    <= to_unsigned(3, ADDR_WIDTH);
        wr_data <= to_signed(27, WIDTH);
        wr_en   <= '1';

        wait until rising_edge(clk);
        wr_en <= '0';

        wait until rising_edge(clk);
        wait for 1 ns;

        assert rd_data = to_signed(27, WIDTH)
            report "tile_buffer_m10k falhou na leitura sincrona."
            severity failure;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
