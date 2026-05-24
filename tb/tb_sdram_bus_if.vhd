library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_sdram_bus_if is
end entity tb_sdram_bus_if;

architecture sim of tb_sdram_bus_if is

    constant CLK_PERIOD : time := 10 ns;
    constant DATA_WIDTH : positive := 32;
    constant ADDR_WIDTH : positive := 8;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal client_req     : std_logic := '0';
    signal client_we      : std_logic := '0';
    signal client_addr    : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal client_wdata   : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal client_byte_en : std_logic_vector((DATA_WIDTH/8)-1 downto 0) := (others => '1');
    signal client_ready   : std_logic;
    signal client_rvalid  : std_logic;
    signal client_rdata   : std_logic_vector(DATA_WIDTH-1 downto 0);

    signal mem_req     : std_logic;
    signal mem_we      : std_logic;
    signal mem_addr    : unsigned(ADDR_WIDTH-1 downto 0);
    signal mem_wdata   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal mem_byte_en : std_logic_vector((DATA_WIDTH/8)-1 downto 0);
    signal mem_ready   : std_logic;
    signal mem_rvalid  : std_logic;
    signal mem_rdata   : std_logic_vector(DATA_WIDTH-1 downto 0);

begin

    clk <= not clk after CLK_PERIOD / 2;

    u_bus : entity work.sdram_bus_if
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            ADDR_WIDTH => ADDR_WIDTH
        )
        port map (
            client_req     => client_req,
            client_we      => client_we,
            client_addr    => client_addr,
            client_wdata   => client_wdata,
            client_byte_en => client_byte_en,
            client_ready   => client_ready,
            client_rvalid  => client_rvalid,
            client_rdata   => client_rdata,
            mem_req        => mem_req,
            mem_we         => mem_we,
            mem_addr       => mem_addr,
            mem_wdata      => mem_wdata,
            mem_byte_en    => mem_byte_en,
            mem_ready      => mem_ready,
            mem_rvalid     => mem_rvalid,
            mem_rdata      => mem_rdata
        );

    u_mem : entity work.sdram_model
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            ADDR_WIDTH => ADDR_WIDTH,
            DEPTH      => 256
        )
        port map (
            clk     => clk,
            rst     => rst,
            req     => mem_req,
            we      => mem_we,
            addr    => mem_addr,
            wdata   => mem_wdata,
            byte_en => mem_byte_en,
            ready   => mem_ready,
            rvalid  => mem_rvalid,
            rdata   => mem_rdata
        );

    stim_proc : process
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        client_addr  <= to_unsigned(5, ADDR_WIDTH);
        client_wdata <= x"CAFEBABE";
        client_we    <= '1';
        client_req   <= '1';
        wait until rising_edge(clk);
        client_req <= '0';
        client_we  <= '0';

        wait until rising_edge(clk);
        client_addr <= to_unsigned(5, ADDR_WIDTH);
        client_req  <= '1';
        wait until rising_edge(clk);
        client_req <= '0';
        wait for 1 ns;

        assert client_ready = '1' and client_rvalid = '1' and client_rdata = x"CAFEBABE"
            report "sdram_bus_if falhou no pass-through."
            severity failure;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
