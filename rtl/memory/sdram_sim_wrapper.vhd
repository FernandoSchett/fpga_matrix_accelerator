library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_sim_wrapper is
    generic (
        DATA_WIDTH : positive := 32;
        ADDR_WIDTH : positive := 18;
        DEPTH      : positive := 262144
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        req     : in std_logic;
        we      : in std_logic;
        addr    : in unsigned(ADDR_WIDTH-1 downto 0);
        wdata   : in std_logic_vector(DATA_WIDTH-1 downto 0);
        byte_en : in std_logic_vector((DATA_WIDTH/8)-1 downto 0);

        ready  : out std_logic;
        rvalid : out std_logic;
        rdata  : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity sdram_sim_wrapper;

architecture sim of sdram_sim_wrapper is
begin

    u_model : entity work.sdram_model
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            ADDR_WIDTH => ADDR_WIDTH,
            DEPTH      => DEPTH
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

end architecture sim;
