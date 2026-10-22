# Stage the CL glue sources for synthesis (issue #54), sourced by the
# HDK build_all.tcl. Same as aws-fpga v2.3.5
# hdk/common/shell_stable/build/scripts/encrypt.tcl: copy
# $CL_DIR/design (and the HDK interface .inc files) into
# src_post_encryption, encrypting only when the build was started
# without --no-encrypt. The Sigil flow always passes --no-encrypt:
# the AFI is meant to be public and rebuildable from this repository
# (the SoC RTL is read straight from rtl/ by synth_cl_sigil.tcl).
if {[llength [glob -nocomplain -dir ${src_post_enc_dir} *]] != 0} {
  eval file delete -force [glob ${src_post_enc_dir}/*]
}
foreach f [glob -directory ${HDK_SHELL_DESIGN_DIR}/interfaces *.inc] {
  file copy -force $f ${src_post_enc_dir}/
}
foreach f [glob -directory ${design_dir} *.{v,sv,vh,svh,inc}] {
  file copy -force $f ${src_post_enc_dir}/
}
exec chmod +w {*}[glob ${src_post_enc_dir}/*]
if {$ENCRYPT} {
  print "Encryption enabled. Encrypting HDL files and DCPs."
  encrypt -k ${HDK_SHELL_DIR}/build/scripts/vivado_keyfile.txt -lang verilog -quiet [glob -nocomplain -- ${src_post_enc_dir}/*.{v,sv,vh,inc}]
} else {
  print "Encryption disabled."
}
