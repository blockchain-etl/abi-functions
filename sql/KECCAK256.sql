CREATE OR REPLACE FUNCTION `abi_functions`.KECCAK256(x STRING) RETURNS STRING LANGUAGE js AS """
  return ethers.utils.keccak256(ethers.utils.toUtf8Bytes(x));
"""
OPTIONS(library="gs://blockchain-etl-bigquery/ethers.js");
