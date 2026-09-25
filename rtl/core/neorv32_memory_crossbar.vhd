-- ================================================================================ --
-- GEMMrv32 - Asymmetric Memory Crossbar                                            --
-- ================================================================================ --
-- Connects a 32-bit CPU and a 256-bit DMA to a single 256-bit memory slave.        --
-- Uses First-Come First-Served (FCFS) arbitration. DMA wins simultaneous ties.     --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity neorv32_memory_crossbar is
  port (
    clk_i   : in  std_ulogic;
    rstn_i  : in  std_ulogic;

    -- Master 1: CPU (32-bit Wishbone-like)
    cpu_req_addr  : in  std_ulogic_vector(31 downto 0);
    cpu_req_wdata : in  std_ulogic_vector(31 downto 0);
    cpu_req_be    : in  std_ulogic_vector(3 downto 0);
    cpu_req_rw    : in  std_ulogic;
    cpu_req_stb   : in  std_ulogic;
    cpu_rsp_rdata : out std_ulogic_vector(31 downto 0);
    cpu_rsp_ack   : out std_ulogic;

    -- Master 2: GEMM Soft DMA (256-bit)
    dma_req_addr  : in  std_ulogic_vector(31 downto 0);
    dma_req_wdata : in  std_ulogic_vector(255 downto 0);
    dma_req_be    : in  std_ulogic_vector(31 downto 0);
    dma_req_rw    : in  std_ulogic;
    dma_req_stb   : in  std_ulogic;
    dma_rsp_rdata : out std_ulogic_vector(255 downto 0);
    dma_rsp_ack   : out std_ulogic;

    -- Slave Port: Memory (256-bit)
    mem_req_addr  : out std_ulogic_vector(31 downto 0);
    mem_req_wdata : out std_ulogic_vector(255 downto 0);
    mem_req_be    : out std_ulogic_vector(31 downto 0);
    mem_req_rw    : out std_ulogic;
    mem_req_stb   : out std_ulogic;
    mem_rsp_rdata : in  std_ulogic_vector(255 downto 0);
    mem_rsp_ack   : in  std_ulogic
  );
end entity;

architecture rtl of neorv32_memory_crossbar is

  type arb_state_t is (ARB_IDLE, ARB_CPU, ARB_DMA);
  signal arb_state : arb_state_t;
  
  -- Latch word select for CPU read alignment
  signal cpu_word_sel : integer range 0 to 7;

begin

  -- FCFS Arbitration State Machine
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        arb_state <= ARB_IDLE;
        cpu_word_sel <= 0;
      else
        case arb_state is
          when ARB_IDLE =>
            if dma_req_stb = '1' then
              arb_state <= ARB_DMA;
            elsif cpu_req_stb = '1' then
              arb_state <= ARB_CPU;
              -- Capture the 32-bit word offset (bits 4:2 of address) for read alignment
              cpu_word_sel <= to_integer(unsigned(cpu_req_addr(4 downto 2)));
            end if;

          when ARB_CPU =>
            if cpu_req_stb = '0' then
              arb_state <= ARB_IDLE;
            end if;

          when ARB_DMA =>
            if dma_req_stb = '0' then
              arb_state <= ARB_IDLE;
            end if;
            
        end case;
      end if;
    end if;
  end process;

  -- Combinational Routing
  process(arb_state, cpu_req_addr, cpu_req_wdata, cpu_req_be, cpu_req_rw, cpu_req_stb,
          dma_req_addr, dma_req_wdata, dma_req_be, dma_req_rw, dma_req_stb, mem_rsp_ack, mem_rsp_rdata, cpu_word_sel)
    variable v_cpu_be_256 : std_ulogic_vector(31 downto 0);
    variable v_cpu_wdata_256 : std_ulogic_vector(255 downto 0);
    variable v_word_idx : integer range 0 to 7;
  begin
    -- Defaults
    mem_req_addr  <= (others => '0');
    mem_req_wdata <= (others => '0');
    mem_req_be    <= (others => '0');
    mem_req_rw    <= '0';
    mem_req_stb   <= '0';
    
    cpu_rsp_rdata <= (others => '0');
    cpu_rsp_ack   <= '0';
    
    dma_rsp_rdata <= (others => '0');
    dma_rsp_ack   <= '0';

    v_word_idx := to_integer(unsigned(cpu_req_addr(4 downto 2)));
    v_cpu_be_256 := (others => '0');
    v_cpu_wdata_256 := (others => '0');

    if arb_state = ARB_CPU then
      -- CPU to Memory Translation
      mem_req_addr <= cpu_req_addr(31 downto 5) & "00000"; -- Align to 32 bytes (256-bit)
      
      -- Shift 32-bit wdata and 4-bit BE into the correct 256-bit lane
      v_cpu_be_256(v_word_idx*4 + 3 downto v_word_idx*4) := cpu_req_be;
      v_cpu_wdata_256(v_word_idx*32 + 31 downto v_word_idx*32) := cpu_req_wdata;
      
      mem_req_wdata <= v_cpu_wdata_256;
      mem_req_be    <= v_cpu_be_256;
      mem_req_rw    <= cpu_req_rw;
      mem_req_stb   <= cpu_req_stb;
      
      -- Route response back
      cpu_rsp_ack <= mem_rsp_ack;
      cpu_rsp_rdata <= mem_rsp_rdata(cpu_word_sel*32 + 31 downto cpu_word_sel*32);

    elsif arb_state = ARB_DMA then
      -- DMA to Memory (Direct 1:1 map)
      mem_req_addr  <= dma_req_addr;
      mem_req_wdata <= dma_req_wdata;
      mem_req_be    <= dma_req_be;
      mem_req_rw    <= dma_req_rw;
      mem_req_stb   <= dma_req_stb;
      
      dma_rsp_ack   <= mem_rsp_ack;
      dma_rsp_rdata <= mem_rsp_rdata;
    else
      -- In ARB_IDLE, we can asynchronously pass through the winning request to save a cycle
      if dma_req_stb = '1' then
        mem_req_addr  <= dma_req_addr;
        mem_req_wdata <= dma_req_wdata;
        mem_req_be    <= dma_req_be;
        mem_req_rw    <= dma_req_rw;
        mem_req_stb   <= '1';
      elsif cpu_req_stb = '1' then
        mem_req_addr <= cpu_req_addr(31 downto 5) & "00000";
        v_cpu_be_256(v_word_idx*4 + 3 downto v_word_idx*4) := cpu_req_be;
        v_cpu_wdata_256(v_word_idx*32 + 31 downto v_word_idx*32) := cpu_req_wdata;
        mem_req_wdata <= v_cpu_wdata_256;
        mem_req_be    <= v_cpu_be_256;
        mem_req_rw    <= cpu_req_rw;
        mem_req_stb   <= '1';
      end if;
    end if;
  end process;

end architecture;
