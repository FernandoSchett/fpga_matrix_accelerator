library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_model is
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
end entity sdram_model;

architecture sim of sdram_model is

    constant BYTE_COUNT : positive := DATA_WIDTH / 8;

    type ram_t is array (0 to DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);

    signal ram        : ram_t := (others => (others => '0'));
    signal ready_reg  : std_logic := '1';
    signal rvalid_reg : std_logic := '0';
    signal rdata_reg  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

begin

    assert DATA_WIDTH mod 8 = 0
        report "sdram_model DATA_WIDTH precisa ser multiplo de 8."
        severity failure;

    ready  <= ready_reg;
    rvalid <= rvalid_reg;
    rdata  <= rdata_reg;

    process(clk, rst)
        variable addr_int : integer;
        variable word     : std_logic_vector(DATA_WIDTH-1 downto 0);
    begin
        if rst = '1' then
            ready_reg  <= '1';
            rvalid_reg <= '0';
            rdata_reg  <= (others => '0');

        elsif rising_edge(clk) then
            ready_reg  <= '1';
            rvalid_reg <= '0';

            if req = '1' then
                addr_int := to_integer(addr);

                if we = '1' then
                    if addr_int < DEPTH then
                        word := ram(addr_int);

                        for byte_idx in 0 to BYTE_COUNT-1 loop
                            if byte_en(byte_idx) = '1' then
                                word(((byte_idx + 1) * 8) - 1 downto byte_idx * 8) :=
                                    wdata(((byte_idx + 1) * 8) - 1 downto byte_idx * 8);
                            end if;
                        end loop;

                        ram(addr_int) <= word;
                    end if;
                else
                    if addr_int < DEPTH then
                        rdata_reg <= ram(addr_int);
                    else
                        rdata_reg <= (others => '0');
                    end if;

                    rvalid_reg <= '1';
                end if;
            end if;
        end if;
    end process;

end architecture sim;
