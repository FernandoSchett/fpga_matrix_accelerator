library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_sdram_model is
end entity tb_sdram_model;

architecture sim of tb_sdram_model is

    constant CLK_PERIOD : time := 10 ns;
    constant DATA_WIDTH : positive := 32;
    constant ADDR_WIDTH : positive := 8;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal req     : std_logic := '0';
    signal we      : std_logic := '0';
    signal addr    : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal wdata   : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal byte_en : std_logic_vector((DATA_WIDTH/8)-1 downto 0) := (others => '1');
    signal ready   : std_logic;
    signal rvalid  : std_logic;
    signal rdata   : std_logic_vector(DATA_WIDTH-1 downto 0);

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.sdram_model
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            ADDR_WIDTH => ADDR_WIDTH,
            DEPTH      => 256
        )
        port map (
            clk     => clk,
            rst     => rst,
            req     => req,
            we      => we,
            addr    => addr,
            wdata   => wdata,
            byte_en => byte_en,
            ready   => ready,
            rvalid  => rvalid,
            rdata   => rdata
        );

    stim_proc : process
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        addr  <= to_unsigned(7, ADDR_WIDTH);
        wdata <= x"12345678";
        we    <= '1';
        req   <= '1';
        wait until rising_edge(clk);
        req <= '0';
        we  <= '0';

        wait until rising_edge(clk);
        addr <= to_unsigned(7, ADDR_WIDTH);
        req  <= '1';
        wait until rising_edge(clk);
        req <= '0';
        wait for 1 ns;

        assert rvalid = '1' and rdata = x"12345678"
            report "sdram_model falhou na leitura apos escrita."
            severity failure;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
