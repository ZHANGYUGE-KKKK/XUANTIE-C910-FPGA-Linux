proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"

  set Page0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "RESET_VECTOR" -parent ${Page0}
  ipgui::add_param $IPINST -name "CPU_APB_BASE" -parent ${Page0}
  ipgui::add_param $IPINST -name "HART_ID" -parent ${Page0}
}

proc update_PARAM_VALUE.RESET_VECTOR { PARAM_VALUE.RESET_VECTOR } {
}

proc validate_PARAM_VALUE.RESET_VECTOR { PARAM_VALUE.RESET_VECTOR } {
  return true
}

proc update_PARAM_VALUE.CPU_APB_BASE { PARAM_VALUE.CPU_APB_BASE } {
}

proc validate_PARAM_VALUE.CPU_APB_BASE { PARAM_VALUE.CPU_APB_BASE } {
  return true
}

proc update_PARAM_VALUE.HART_ID { PARAM_VALUE.HART_ID } {
}

proc validate_PARAM_VALUE.HART_ID { PARAM_VALUE.HART_ID } {
  return true
}

proc update_MODELPARAM_VALUE.RESET_VECTOR { MODELPARAM_VALUE.RESET_VECTOR PARAM_VALUE.RESET_VECTOR } {
  set_property value [get_property value ${PARAM_VALUE.RESET_VECTOR}] ${MODELPARAM_VALUE.RESET_VECTOR}
}

proc update_MODELPARAM_VALUE.CPU_APB_BASE { MODELPARAM_VALUE.CPU_APB_BASE PARAM_VALUE.CPU_APB_BASE } {
  set_property value [get_property value ${PARAM_VALUE.CPU_APB_BASE}] ${MODELPARAM_VALUE.CPU_APB_BASE}
}

proc update_MODELPARAM_VALUE.HART_ID { MODELPARAM_VALUE.HART_ID PARAM_VALUE.HART_ID } {
  set_property value [get_property value ${PARAM_VALUE.HART_ID}] ${MODELPARAM_VALUE.HART_ID}
}
