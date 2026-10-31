; p9_cross: load-use 阻塞与分支纠正交叉（P2 第③条）
;
; 构造：ld.w 后紧跟依赖该结果的 beq，ID 必须等 load 数据才能发射；
;       此时 IF 已经把错误路径的 addi 取了进来。
;       判据：纠正必须在 beq 真正发射那一拍生效，错误路径不进 EXE。
;       若纠正丢失或在阻塞期间被清掉，r6 会被写成 0x5ad。
; 期望：r6 = 3，mem[0] = 3
        li     r4, 0x1c100000
        li     r5, 3
        li     r6, 0
loop:
        ld.w   r7, r4, 8
        beq    r7, r0, skip
        addi.w r6, r0, 0x5ad
skip:
        addi.w r6, r6, 1
        addi.w r5, r5, -1
        bne    r5, r0, loop
        st.w   r6, r4, 0
        st.w   r0, r4, 0x100
done:
        b      done
