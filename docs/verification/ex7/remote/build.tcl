set root [file dirname [file normalize [info script]]]
set_param general.maxThreads 8
create_project remote_ex7 $root/project -part xc7a200tfbg676-1
add_files [glob $root/myCPU/*.v]
add_files [glob $root/soc_verify/soc_bram/rtl/*.v]
add_files [glob $root/soc_verify/soc_bram/rtl/*/*.v]
add_files [glob $root/soc_verify/soc_bram/rtl/xilinx_ip/*/*.xci]
add_files [list $root/remote2local.v $root/loongson_remote_top.v]
add_files -fileset constrs_1 $root/loongson_remote.xdc
set_property top looongson_remote_top [get_filesets sources_1]
upgrade_ip [get_ips]
set_property CONFIG.PRIM_IN_FREQ 50.000 [get_ips clk_pll]
set_property CONFIG.Coe_File $root/func/obj/inst_ram.coe [get_ips inst_ram]
set_property generate_synth_checkpoint false [get_files *.xci]
generate_target all [get_ips]
update_compile_order -fileset sources_1
report_compile_order -file $root/compile_order.txt
synth_design -top looongson_remote_top -part xc7a200tfbg676-1
report_utilization -file $root/utilization.rpt
report_drc -file $root/synthesis_drc.rpt
write_checkpoint $root/remote_ex7_synth.dcp
opt_design
place_design
phys_opt_design
route_design
write_checkpoint $root/remote_ex7_routed.dcp
report_timing_summary -file $root/timing_initial.rpt
set paths [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $paths] && [get_property SLACK [lindex $paths 0]] < 0} {
    set initial_slack [get_property SLACK [lindex $paths 0]]
    phys_opt_design -directive AggressiveExplore
    route_design -directive Explore
    set optimized_paths [get_timing_paths -quiet -delay_type max -max_paths 1]
    set optimized_slack [get_property SLACK [lindex $optimized_paths 0]]
    write_checkpoint $root/remote_ex7_optimized.dcp
    if {$optimized_slack < $initial_slack} {
        close_design
        open_checkpoint $root/remote_ex7_routed.dcp
    }
}
report_timing_summary -file $root/timing_summary.rpt
report_drc -file $root/implementation_drc.rpt
report_route_status -file $root/route_status.rpt
write_checkpoint $root/remote_ex7_final.dcp
write_bitstream -force $root/ex7_remote.bit
close_project
