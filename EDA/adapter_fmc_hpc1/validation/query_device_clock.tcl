# Read-only device inventory in an in-memory IO-planning design; no synthesis.
create_project -in_memory -part xcvu9p-flga2104-2L-e
set_property design_mode PinPlanning [current_fileset]
open_io_design -name clock_pin_inventory
foreach ball {E12 D12 AW26 AW27 AW23 AW22 AY24 AY23 AY9 BA9 BC9 BC8 AW12 AJ13} {
    set pkg [get_package_pins $ball]
    set site [get_sites -of_objects $pkg]
    set cr [get_clock_regions -of_objects $site]
    set slr [get_slrs -of_objects $site]
    puts "PIN_RECORD $ball BANK=[get_property BANK $pkg] SITE=$site CR=$cr SLR=$slr"
}
foreach cr {X4Y5 X4Y7 X4Y8} {
    puts "BUFG_RECORD $cr [get_sites -of_objects [get_clock_regions $cr] -filter {SITE_TYPE =~ BUFG*}]"
}
close_project
exit
