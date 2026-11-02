// Copyright 2026 Noverberrain.
// SPDX-License-Identifier: Apache-2.0

///|
// Same native exit convention as core/async's command-line test programs.
extern "C" fn exit(code : Int32) = "exit"

///|
async fn main {
  let args = @env.args()
  let code = @cli.run(args[1:])
  if code != 0 {
    exit(code)
  }
}
