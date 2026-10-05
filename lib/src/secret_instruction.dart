// VERIFY, CHANGE REFERENCE DATA, RESET RETRY COUNTER.
const _secretInstructions = {0x20, 0x24, 0x2C};

/// Whether the data of a command with instruction [ins] holds a PIN or PUK.
bool isSecretInstruction(int ins) => _secretInstructions.contains(ins);
