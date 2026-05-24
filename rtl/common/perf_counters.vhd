library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity perf_counters is
    generic (
        COUNTER_WIDTH : positive := 64
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        clear  : in std_logic;
        enable : in std_logic;

        event_sdram_read  : in std_logic;
        event_sdram_write : in std_logic;
        event_mac_group   : in std_logic;

        cycle_count       : out unsigned(COUNTER_WIDTH-1 downto 0);
        sdram_read_count  : out unsigned(COUNTER_WIDTH-1 downto 0);
        sdram_write_count : out unsigned(COUNTER_WIDTH-1 downto 0);
        mac_group_count   : out unsigned(COUNTER_WIDTH-1 downto 0)
    );
end entity perf_counters;

architecture rtl of perf_counters is

    signal cycles_reg       : unsigned(COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal sdram_reads_reg  : unsigned(COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal sdram_writes_reg : unsigned(COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal mac_groups_reg   : unsigned(COUNTER_WIDTH-1 downto 0) := (others => '0');

begin

    cycle_count       <= cycles_reg;
    sdram_read_count  <= sdram_reads_reg;
    sdram_write_count <= sdram_writes_reg;
    mac_group_count   <= mac_groups_reg;

    process(clk, rst)
    begin
        if rst = '1' then
            cycles_reg       <= (others => '0');
            sdram_reads_reg  <= (others => '0');
            sdram_writes_reg <= (others => '0');
            mac_groups_reg   <= (others => '0');

        elsif rising_edge(clk) then
            if clear = '1' then
                cycles_reg       <= (others => '0');
                sdram_reads_reg  <= (others => '0');
                sdram_writes_reg <= (others => '0');
                mac_groups_reg   <= (others => '0');
            else
                if enable = '1' then
                    cycles_reg <= cycles_reg + 1;
                end if;

                if event_sdram_read = '1' then
                    sdram_reads_reg <= sdram_reads_reg + 1;
                end if;

                if event_sdram_write = '1' then
                    sdram_writes_reg <= sdram_writes_reg + 1;
                end if;

                if event_mac_group = '1' then
                    mac_groups_reg <= mac_groups_reg + 1;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
