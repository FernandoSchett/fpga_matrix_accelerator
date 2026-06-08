library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity uart_byte_fifo is
    generic (
        FIFO_DEPTH       : positive := 64;
        ALMOST_FULL_LEVEL : natural := 60;
        RAM_BLOCK_TYPE   : string := "M10K"
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        wr_en   : in std_logic;
        wr_data : in std_logic_vector(7 downto 0);

        rd_en   : in std_logic;
        rd_data : out std_logic_vector(7 downto 0);

        empty       : out std_logic;
        full        : out std_logic;
        almost_full : out std_logic;
        overflow    : out std_logic;
        underflow   : out std_logic
    );
end entity uart_byte_fifo;

architecture rtl of uart_byte_fifo is

    function clog2_local(constant value : positive) return positive is
        variable result : positive := 1;
        variable power  : positive := 2;
    begin
        while power < value loop
            power  := power * 2;
            result := result + 1;
        end loop;

        return result;
    end function;

    constant USEDW_WIDTH : positive := clog2_local(FIFO_DEPTH);

    signal fifo_empty       : std_logic;
    signal fifo_full        : std_logic;
    signal fifo_almost_full : std_logic;
    signal fifo_wrreq       : std_logic;
    signal fifo_rdreq       : std_logic;
    signal usedw_unused     : std_logic_vector(USEDW_WIDTH-1 downto 0);
    signal almost_empty_unused : std_logic;
    signal eccstatus_unused : std_logic_vector(1 downto 0);

    signal overflow_reg  : std_logic := '0';
    signal underflow_reg : std_logic := '0';

begin

    fifo_wrreq <= wr_en and not fifo_full;
    fifo_rdreq <= rd_en and not fifo_empty;

    empty       <= fifo_empty;
    full        <= fifo_full;
    almost_full <= fifo_almost_full;
    overflow    <= overflow_reg;
    underflow   <= underflow_reg;

    u_scfifo : scfifo
        generic map (
            lpm_width               => 8,
            lpm_widthu              => USEDW_WIDTH,
            lpm_numwords            => FIFO_DEPTH,
            lpm_showahead           => "ON",
            lpm_hint                => "USE_EAB=ON",
            ram_block_type          => RAM_BLOCK_TYPE,
            intended_device_family  => "Cyclone V",
            almost_full_value       => ALMOST_FULL_LEVEL,
            almost_empty_value      => 1,
            overflow_checking       => "ON",
            underflow_checking      => "ON",
            allow_rwcycle_when_full => "OFF",
            add_ram_output_register => "OFF",
            use_eab                 => "ON",
            lpm_type                => "scfifo"
        )
        port map (
            data         => wr_data,
            clock        => clk,
            wrreq        => fifo_wrreq,
            rdreq        => fifo_rdreq,
            aclr         => '0',
            sclr         => rst,
            full         => fifo_full,
            almost_full  => fifo_almost_full,
            empty        => fifo_empty,
            almost_empty => almost_empty_unused,
            eccstatus    => eccstatus_unused,
            q            => rd_data,
            usedw        => usedw_unused
        );

    process(clk, rst)
    begin
        if rst = '1' then
            overflow_reg  <= '0';
            underflow_reg <= '0';
        elsif rising_edge(clk) then
            overflow_reg  <= wr_en and fifo_full;
            underflow_reg <= rd_en and fifo_empty;
        end if;
    end process;

end architecture rtl;
