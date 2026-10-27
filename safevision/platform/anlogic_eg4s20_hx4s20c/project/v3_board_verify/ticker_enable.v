// Explicit production feature selection. Legacy simulation manifests retain
// their original mode file and exercise the unchanged disabled interface.
`undef SAFEVISION_TICKER_ENABLE
`define SAFEVISION_TICKER_ENABLE 1
