library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_bus_if is
    generic (
        DATA_WIDTH    : positive := 32;
        ADDR_WIDTH    : positive := 18;
        READ_LATENCY  : natural  := 3;
        WRITE_LATENCY : natural  := 2
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        client_rd_req   : in std_logic;
        client_rd_addr  : in unsigned(ADDR_WIDTH-1 downto 0);
        client_rd_data  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        client_rd_valid : out std_logic;
        client_rd_ready : out std_logic;

        client_wr_req   : in std_logic;
        client_wr_addr  : in unsigned(ADDR_WIDTH-1 downto 0);
        client_wr_data  : in std_logic_vector(DATA_WIDTH-1 downto 0);
        client_wr_ready : out std_logic;

        client_busy : out std_logic;

        mem_rd_req   : out std_logic;
        mem_rd_addr  : out unsigned(ADDR_WIDTH-1 downto 0);
        mem_rd_data  : in std_logic_vector(DATA_WIDTH-1 downto 0);
        mem_rd_valid : in std_logic;
        mem_rd_ready : in std_logic;

        mem_wr_req   : out std_logic;
        mem_wr_addr  : out unsigned(ADDR_WIDTH-1 downto 0);
        mem_wr_data  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        mem_wr_ready : in std_logic;

        mem_busy : in std_logic
    );
end entity sdram_bus_if;

architecture rtl of sdram_bus_if is
begin

    mem_rd_req  <= client_rd_req;
    mem_rd_addr <= client_rd_addr;

    client_rd_data  <= mem_rd_data;
    client_rd_valid <= mem_rd_valid;
    client_rd_ready <= mem_rd_ready;

    mem_wr_req  <= client_wr_req;
    mem_wr_addr <= client_wr_addr;
    mem_wr_data <= client_wr_data;

    client_wr_ready <= mem_wr_ready;
    client_busy     <= mem_busy;

end architecture rtl;
