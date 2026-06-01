library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity memory_manager is
    generic (
        ADDR_WIDTH : positive := 25;
        DATA_WIDTH : positive := 32
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        host_valid  : in std_logic;
        host_write  : in std_logic;
        host_addr   : in unsigned(ADDR_WIDTH-1 downto 0);
        host_wdata  : in std_logic_vector(DATA_WIDTH-1 downto 0);
        host_be     : in std_logic_vector((DATA_WIDTH/8)-1 downto 0);
        host_ready  : out std_logic;
        host_rvalid : out std_logic;
        host_rdata  : out std_logic_vector(DATA_WIDTH-1 downto 0);

        loader_rd_req   : in std_logic;
        loader_rd_addr  : in unsigned(ADDR_WIDTH-1 downto 0);
        loader_rd_ready : out std_logic;
        loader_rd_valid : out std_logic;
        loader_rd_data  : out std_logic_vector(DATA_WIDTH-1 downto 0);

        writer_wr_req   : in std_logic;
        writer_wr_addr  : in unsigned(ADDR_WIDTH-1 downto 0);
        writer_wr_data  : in std_logic_vector(DATA_WIDTH-1 downto 0);
        writer_wr_be    : in std_logic_vector((DATA_WIDTH/8)-1 downto 0);
        writer_wr_ready : out std_logic;

        sdram_cmd_valid : out std_logic;
        sdram_cmd_write : out std_logic;
        sdram_cmd_addr  : out unsigned(ADDR_WIDTH-1 downto 0);
        sdram_cmd_wdata : out std_logic_vector(DATA_WIDTH-1 downto 0);
        sdram_cmd_be    : out std_logic_vector((DATA_WIDTH/8)-1 downto 0);
        sdram_cmd_ready : in std_logic;
        sdram_rd_valid  : in std_logic;
        sdram_rd_data   : in std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity memory_manager;

architecture rtl of memory_manager is

    type pending_read_t is (READ_NONE, READ_HOST, READ_LOADER);
    signal pending_read : pending_read_t := READ_NONE;

    signal can_issue : std_logic;

begin

    can_issue <= '1' when pending_read = READ_NONE else '0';

    process(host_valid, host_write, host_addr, host_wdata, host_be,
            loader_rd_req, loader_rd_addr, writer_wr_req, writer_wr_addr,
            writer_wr_data, writer_wr_be, sdram_cmd_ready, can_issue)
    begin
        sdram_cmd_valid <= '0';
        sdram_cmd_write <= '0';
        sdram_cmd_addr  <= (others => '0');
        sdram_cmd_wdata <= (others => '0');
        sdram_cmd_be    <= (others => '0');

        host_ready      <= '0';
        loader_rd_ready <= '0';
        writer_wr_ready <= '0';

        if can_issue = '1' then
            if host_valid = '1' then
                sdram_cmd_valid <= '1';
                sdram_cmd_write <= host_write;
                sdram_cmd_addr  <= host_addr;
                sdram_cmd_wdata <= host_wdata;
                sdram_cmd_be    <= host_be;
                host_ready      <= sdram_cmd_ready;

            elsif writer_wr_req = '1' then
                sdram_cmd_valid <= '1';
                sdram_cmd_write <= '1';
                sdram_cmd_addr  <= writer_wr_addr;
                sdram_cmd_wdata <= writer_wr_data;
                sdram_cmd_be    <= writer_wr_be;
                writer_wr_ready <= sdram_cmd_ready;

            elsif loader_rd_req = '1' then
                sdram_cmd_valid <= '1';
                sdram_cmd_write <= '0';
                sdram_cmd_addr  <= loader_rd_addr;
                loader_rd_ready <= sdram_cmd_ready;
            end if;
        end if;
    end process;

    process(clk, rst)
    begin
        if rst = '1' then
            pending_read <= READ_NONE;

        elsif rising_edge(clk) then
            if sdram_rd_valid = '1' then
                pending_read <= READ_NONE;

            elsif pending_read = READ_NONE and sdram_cmd_ready = '1' then
                if host_valid = '1' and host_write = '0' then
                    pending_read <= READ_HOST;
                elsif host_valid = '0' and writer_wr_req = '0' and loader_rd_req = '1' then
                    pending_read <= READ_LOADER;
                end if;
            end if;
        end if;
    end process;

    host_rvalid     <= sdram_rd_valid when pending_read = READ_HOST else '0';
    host_rdata      <= sdram_rd_data;
    loader_rd_valid <= sdram_rd_valid when pending_read = READ_LOADER else '0';
    loader_rd_data  <= sdram_rd_data;

end architecture rtl;
