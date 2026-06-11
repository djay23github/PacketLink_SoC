#ECO that improved _5443_/Q -> u_serdes_top/tx_valid
# Re-run from clean DB, then apply this ECO
remove_buffers max_cap494
remove_buffers max_cap464
remove_buffers output262
estimate_parasitics -global_routing
