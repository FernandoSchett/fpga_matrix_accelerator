library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_sim_wrapper is
    generic (
        DATA_WIDTH    : positive := 32;
        ADDR_WIDTH    : positive := 18;
        READ_LATENCY  : natural  := 3;
        WRITE_LATENCY : natural  := 2;
        DEPTH         : positive := 262144
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        rd_req   : in std_logic;
        rd_addr  : in unsigned(ADDR_WIDTH-1 downto 0);
        rd_data  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        rd_valid : out std_logic;
        rd_ready : out std_logic;

        wr_req   : in std_logic;
        wr_addr  : in unsigned(ADDR_WIDTH-1 downto 0);
        wr_data  : in std_logic_vector(DATA_WIDTH-1 downto 0);
        wr_ready : out std_logic;

        busy : out std_logic
    );
end entity sdram_sim_wrapper;

architecture sim of sdram_sim_wrapper is
begin

    u_model : entity work.sdram_model
        generic map (
            DATA_WIDTH    => DATA_WIDTH,
            ADDR_WIDTH    => ADDR_WIDTH,
            READ_LATENCY  => READ_LATENCY,
            WRITE_LATENCY => WRITE_LATENCY,
            DEPTH         => DEPTH
        )
        port map (
            clk      => clk,
            rst      => rst,
            rd_req   => rd_req,
            rd_addr  => rd_addr,
            rd_data  => rd_data,
            rd_valid => rd_valid,
            rd_ready => rd_ready,
            wr_req   => wr_req,
            wr_addr  => wr_addr,
            wr_data  => wr_data,
            wr_ready => wr_ready,
            busy     => busy
        );

end architecture sim;
