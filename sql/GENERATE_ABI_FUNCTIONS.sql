CREATE OR REPLACE FUNCTION `abi_functions`.GENERATE_ABI_FUNCTIONS(prefix STRING, abi STRING) RETURNS STRUCT<functions ARRAY<STRING>, events ARRAY<STRING>> LANGUAGE js AS """
  abi = JSON.parse(abi);
  rr = [];
  res_functions = [];
  res_events = [];
  abi.forEach(function(el) {
    q3 = '"'+'"'+'"';
    if (el.type == "function") {
      inputs = [];
      name = el.name;
      el.inputs.forEach(function(ii) {
        inputs.push(ii.name);
      });
      res_functions.push(
        "CREATE TEMP FUNCTION "+prefix+"_call_"+name+"(kv ARRAY<STRUCT<arg STRING,val STRING>>) RETURNS STRUCT<"+inputs.map(x=>x+" STRING").join(",")+"> LANGUAGE js AS "+q3+"\\n"+
        "want=new Set(["+inputs.map(x=>"'"+x+"'").join(",")+"]);res=[];kv.forEach(function(el){if(want.has(el.arg)){res[el.arg]=el.val}});return res;\\n"+q3+"\\n"+
        'OPTIONS(library="gs://blockchain-etl-bigquery/ethers.js");'+"\\n"
      );
    }
    else if (el.type == "event") {
      inputs = [];
      name = el.name;
      el.inputs.forEach(function(ii) {
        inputs.push(ii.name);
      });
      res_events.push(
        "CREATE TEMP FUNCTION "+prefix+"_evt_"+name+"(kv ARRAY<STRUCT<arg STRING,val STRING>>) RETURNS STRUCT<"+inputs.map(x=>x+" STRING").join(",")+"> LANGUAGE js AS "+q3+"\\n"+
        "want=new Set(["+inputs.map(x=>"'"+x+"'").join(",")+"]);res=[];kv.forEach(function(el){if(want.has(el.arg)){res[el.arg]=el.val}});return res;\\n"+q3+"\\n"+
        'OPTIONS(library="gs://blockchain-etl-bigquery/ethers.js");'+"\\n"
      );
    }
  });
  rr.functions = res_functions;
  rr.events = res_events;
  return rr;
"""
OPTIONS(library="gs://blockchain-etl-bigquery/ethers.js");
