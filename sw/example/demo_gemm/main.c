#include <neorv32.h>
#include <string.h>

#define BAUD_RATE 1920000
#define DIM 16

// Statically initialized to 1
int8_t A[DIM * DIM] __attribute__((aligned(4)));
int8_t B[DIM * DIM] __attribute__((aligned(4)));
int32_t C[DIM * DIM] __attribute__((aligned(4)));
int32_t C_ref[DIM * DIM] __attribute__((aligned(4)));

/* Print a 32-bit integer in decimal without using printf */
static void print_dec32(uint32_t v) {
    if (v == 0) {
        neorv32_uart0_putc('0');
        return;
    }
    char buf[12];
    int i = 0;
    while (v > 0) {
        buf[i++] = (v % 10) + '0';
        v /= 10;
    }
    while (i > 0) {
        neorv32_uart0_putc(buf[--i]);
    }
}

static uint32_t lfsr = 0xACE1u;
static uint32_t rand_num(void) {
    unsigned bit = ((lfsr >> 0) ^ (lfsr >> 2) ^ (lfsr >> 3) ^ (lfsr >> 5)) & 1;
    lfsr = (lfsr >> 1) | (bit << 15);
    return lfsr;
}

int main(void) {
    neorv32_rte_setup();
    neorv32_uart0_setup(BAUD_RATE, 0);

    neorv32_uart0_printf("\n\n=== NEORV32 GEMM Hardware vs CPU Test ===\n");

    neorv32_uart0_printf("1. Initializing random A and B matrices...\n");
    for (int i = 0; i < DIM * DIM; i++) {
        // Keep values small to avoid overflow in sum of 16 products
        A[i] = (int8_t)(rand_num() % 16) - 8; 
        B[i] = (int8_t)(rand_num() % 16) - 8;
        C[i] = 0;
        C_ref[i] = 0;
    }

    neorv32_uart0_printf("2. Running CPU GEMM...\n");
    uint32_t cpu_start = (uint32_t)neorv32_cpu_get_cycle();
    for (int i = 0; i < DIM; i++) {
        for (int j = 0; j < DIM; j++) {
            int32_t sum = 0;
            for (int k = 0; k < DIM; k++) {
                sum += (int32_t)A[i * DIM + k] * (int32_t)B[k * DIM + j];
            }
            C_ref[i * DIM + j] = sum;
        }
    }
    uint32_t cpu_end = (uint32_t)neorv32_cpu_get_cycle();

    neorv32_uart0_printf("3. Configuring and running HW Accelerator...\n");
    NEORV32_CFS->REG[0] = (uint32_t)A;
    NEORV32_CFS->REG[1] = (uint32_t)B;
    NEORV32_CFS->REG[2] = (uint32_t)C;
    NEORV32_CFS->REG[3] = DIM;
    NEORV32_CFS->REG[4] = DIM;

    uint32_t hw_start = (uint32_t)neorv32_cpu_get_cycle();
    asm volatile ("fence" ::: "memory");
    NEORV32_CFS->REG[5] = 1; // START

    // Poll DONE bit (bit 2 of REG[5])
    while ((NEORV32_CFS->REG[5] & (1 << 2)) == 0) {}
    NEORV32_CFS->REG[5] = 0;
    asm volatile ("fence" ::: "memory");
    uint32_t hw_end = (uint32_t)neorv32_cpu_get_cycle();

    neorv32_uart0_printf("4. Verification...\n");
    int errors = 0;
    for (int i = 0; i < DIM * DIM; i++) {
        if (C[i] != C_ref[i]) {
            errors++;
        }
    }

    if (errors == 0) {
        neorv32_uart0_printf("\n##################################\n");
        neorv32_uart0_printf("# SUCCESS! Hardware GEMM passed! #\n");
        neorv32_uart0_printf("##################################\n");
        
        neorv32_uart0_printf("\n--- Performance Results ---\n");
        neorv32_uart0_printf("CPU cycles: "); print_dec32(cpu_end - cpu_start); neorv32_uart0_printf("\n");
        neorv32_uart0_printf("HW cycles : "); print_dec32(hw_end - hw_start); neorv32_uart0_printf("\n");
        
        uint32_t speedup = (cpu_end - cpu_start) / (hw_end - hw_start);
        neorv32_uart0_printf("Speedup   : "); print_dec32(speedup); neorv32_uart0_printf("x\n");
    } else {
        neorv32_uart0_printf("\nFAILED: errors found.\n");
    }

    return 0;
}
