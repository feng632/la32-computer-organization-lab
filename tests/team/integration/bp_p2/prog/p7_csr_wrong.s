; p7_csr_wrong: 错误路径上的 CSR 写不得生效（P2 第②条：CSR 写副作用）
;
; 构造：beq 恒成立，紧随其后的 csrwr 与 addi 属于错误路径。
;       循环 3 次，第 1 次 BTB 无条目（cold 纠正），第 2、3 次命中且预测跳转。
; 判据：save0 必须仍为 0（r7 读回 0）；r6 必须仍是 0x5a5a（csrwr 未执行，未被回写旧值）。
;       若 csrwr 误执行：save0 变成 0x5a5a（r7 读到 0x5a5a），且 r6 被写成旧值 0。
        li     r4, 0x1c100000
        li     r6, 0x5a5a
        li     r5, 3
loop:
        beq    r5, r5, skip
        csrwr  r6, save0
        addi.w r9, r0, 0x5ad
skip:
        addi.w r5, r5, -1
        bne    r5, r0, loop
        csrrd  r7, save0
        st.w   r7, r4, 0
        st.w   r6, r4, 4
        st.w   r0, r4, 0x100
done:
        b      done
