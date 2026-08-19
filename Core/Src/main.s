/* ====================================================================
   Proyecto: Sumador Multiplexado (8 bits) - SIN LEDs INDICADORES
   Target:   STM32F103 (Proteus / Blue Pill)
   Reloj:    HSI Interno (8 MHz)

   ENTRADAS:
   - PA0 - PA7  -> DIP Switch (Datos A y B)
   - PC14       -> Pulsador de control (Pull-Up)

   SALIDAS:
   - PB3 - PB10 -> Resultado Suma (8 bits)
   - PB11       -> Acarreo / Carry Out (1 bit)
   ==================================================================== */

    .syntax unified
    .cpu cortex-m3
    .thumb

    .text
    .align 2
    .global main
    .global Reset_Handler
    .type main, %function
    .type Reset_Handler, %function
    .thumb_func

/* --- Direcciones de Registros RCC, AFIO y GPIO --- */
.equ RCC_APB2ENR,     0x40021018

.equ AFIO_BASE,       0x40010000
.equ AFIO_MAPR,       (AFIO_BASE + 0x04)

.equ GPIOA_CRL,       0x40010800
.equ GPIOA_CRH,       0x40010804
.equ GPIOA_IDR,       0x40010808
.equ GPIOA_ODR,       0x4001080C

.equ GPIOB_CRL,       0x40010C00
.equ GPIOB_CRH,       0x40010C04
.equ GPIOB_ODR,       0x40010C0C

.equ GPIOC_CRH,       0x40011004
.equ GPIOC_IDR,       0x40011008
.equ GPIOC_ODR,       0x4001100C

Reset_Handler:
main:
    cpsid i                       @ Deshabilitar interrupciones durante inicialización

    /* 1. Habilitar reloj para AFIO, GPIOA, GPIOB y GPIOC */
    LDR R0, =RCC_APB2ENR
    LDR R1, [R0]
    ORR R1, R1, #(1 << 0) | (1 << 2) | (1 << 3) | (1 << 4)
    STR R1, [R0]

    /* 2. Deshabilitar JTAG en AFIO_MAPR para liberar PB3 y PB4 como GPIOs */
    LDR R0, =AFIO_MAPR
    LDR R1, [R0]
    BIC R1, R1, #(0x7 << 24)
    ORR R1, R1, #(0x2 << 24)
    STR R1, [R0]

    /* 3. Configurar PA0-PA7 como ENTRADAS Digitales Floating */
    LDR R0, =GPIOA_CRL
    LDR R1, =0x44444444
    STR R1, [R0]

    /* 4. Configurar PB3-PB10 como SALIDAS Push-Pull 2MHz */
    /*    PB3-PB7 están en CRL (bits 12-31) */
    LDR R0, =GPIOB_CRL
    LDR R1, [R0]
    /* Configurar PB3-PB7 como salidas (0x22222 << 12) */
    /* Limpiar bits 12-31 (PB3-PB7) */
    MOV R2, #0xFFFF
    LSL R2, R2, #16                @ R2 = 0xFFFF0000
    BIC R1, R1, R2                 @ Limpiar bits 16-31
    MOV R2, #0xF
    LSL R2, R2, #12                @ R2 = 0xF000
    BIC R1, R1, R2                 @ Limpiar bits 12-15
    /* Configurar PB3-PB7 como salidas (0x2 para cada pin) */
    MOV R2, #0x2
    ORR R1, R1, R2, LSL #12        @ PB3 = 0x2
    MOV R2, #0x2
    ORR R1, R1, R2, LSL #16        @ PB4 = 0x2
    MOV R2, #0x2
    ORR R1, R1, R2, LSL #20        @ PB5 = 0x2
    MOV R2, #0x2
    ORR R1, R1, R2, LSL #24        @ PB6 = 0x2
    MOV R2, #0x2
    ORR R1, R1, R2, LSL #28        @ PB7 = 0x2
    STR R1, [R0]

    /* 5. Configurar PB8-PB11 como SALIDAS (están en CRH) */
    LDR R0, =GPIOB_CRH
    LDR R1, [R0]
    /* Limpiar bits 0-15 (PB8-PB11) */
    MOV R2, #0xFFFF
    BIC R1, R1, R2                 @ Limpiar bits 0-15
    /* Configurar PB8-PB11 como salidas (0x2 para cada pin) */
    MOV R2, #0x2
    ORR R1, R1, R2, LSL #0         @ PB8 = 0x2
    MOV R2, #0x2
    ORR R1, R1, R2, LSL #4         @ PB9 = 0x2
    MOV R2, #0x2
    ORR R1, R1, R2, LSL #8         @ PB10 = 0x2
    MOV R2, #0x2
    ORR R1, R1, R2, LSL #12        @ PB11 = 0x2
    STR R1, [R0]

    /* 6. Configurar PC14 como ENTRADA Digital con Pull-Up */
    LDR R0, =GPIOC_CRH
    LDR R1, [R0]
    BIC R1, R1, #(0x0F << 24)         @ Limpiar configuración de PC14
    ORR R1, R1, #(0x08 << 24)         @ 0x08 = Input con Pull-Up/Pull-Down
    STR R1, [R0]

    /* Activar Pull-UP en PC14 */
    LDR R0, =GPIOC_ODR
    LDR R1, [R0]
    ORR R1, R1, #(1 << 14)            @ Activar Pull-Up en PC14
    STR R1, [R0]

/* --- INICIO DE LA MÁQUINA DE ESTADOS --- */
inicio_proceso:
    /* REPOSO INICIAL: Limpiar todas las salidas del Puerto B */
    LDR R0, =GPIOB_ODR
    MOV R1, #0
    STR R1, [R0]

/* --- 1. CAPTURA DEL DATO A --- */
    /* Esperar la primera pulsación en PC14 */
    BL esperar_pulsacion

    /* Leer Dato A de PA0-PA7 */
    LDR R0, =GPIOA_IDR
    LDR R4, [R0]
    AND R4, R4, #0xFF                @ R4 = Dato A

    /* Limpiar salidas después de capturar A */
    LDR R0, =GPIOB_ODR
    MOV R1, #0
    STR R1, [R0]

/* --- 2. CAPTURA DEL DATO B --- */
    /* Esperar la segunda pulsación en PC14 */
    BL esperar_pulsacion

    /* Leer Dato B de PA0-PA7 */
    LDR R0, =GPIOA_IDR
    LDR R5, [R0]
    AND R5, R5, #0xFF                @ R5 = Dato B

    /* Limpiar salidas después de capturar B */
    LDR R0, =GPIOB_ODR
    MOV R1, #0
    STR R1, [R0]

/* --- 3. CÁLCULO Y MUESTRA DE LA SUMA --- */
    /* Esperar la tercera pulsación en PC14 */
    BL esperar_pulsacion

    /* Sumar R4 + R5 y guardar el resultado en R6 */
    MOV R6, R4
    ADD R6, R6, R5                   @ R6 = R4 + R5

    /* Preparar salidas */
    LDR R0, =GPIOB_ODR
    MOV R1, #0
    STR R1, [R0]                     @ Limpiar todas las salidas

    /* Mostrar resultado en PB3-PB10 (8 bits) */
    /* El resultado se coloca en los bits 3-10 */
    LSL R1, R6, #3                   @ Desplazar resultado a PB3-PB10

    /* Verificar acarreo (suma > 255) */
    CMP R6, #0xFF
    BLE no_carry_sum
    ORR R1, R1, #(1 << 11)           @ Activar PB11 (Carry)
no_carry_sum:

    STR R1, [R0]                     @ Escribir en GPIOB_ODR

/* --- 4. REINICIO DE LA SECUENCIA --- */
    /* Esperar la cuarta pulsación en PC14 */
    BL esperar_pulsacion

    /* Salta a inicio_proceso para reiniciar */
    B inicio_proceso

/* Bucle de seguridad */
bucle_seguridad:
    B bucle_seguridad

/* ====================================================================
   SUBRUTINA: esperar_pulsacion (para PC14)
   Sincroniza la lectura del pulsador PC14 (detecta presionar y soltar)
   ==================================================================== */
esperar_pulsacion:
    LDR R0, =GPIOC_IDR

    /* Esperar que el pulsador esté en reposo (1) */
esperar_reposo:
    LDR R1, [R0]
    TST R1, #(1 << 14)               @ Verificar PC14
    BNE esperar_reposo               @ Si es 1, sigue esperando

    /* Delay antirrebote al presionar */
    LDR R2, =10000
delay_presionar:
    SUBS R2, R2, #1
    BNE delay_presionar

    /* Esperar que se suelte el pulsador (vuelva a 1) */
esperar_soltar:
    LDR R1, [R0]
    TST R1, #(1 << 14)
    BEQ esperar_soltar               @ Si es 0, sigue esperando

    /* Delay antirrebote al soltar */
    LDR R2, =10000
delay_soltar:
    SUBS R2, R2, #1
    BNE delay_soltar

    BX LR
