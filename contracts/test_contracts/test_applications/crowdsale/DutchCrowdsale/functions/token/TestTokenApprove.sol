pragma solidity ^0.4.21;

// TokenApprove with additional testing features
contract TestTokenApprove {

  // Storage address to read from - readMulti and readSingle functions read from this address
  address public app_storage;

  // Keeps track of the last storage return
  bytes32[] public last_storage_event;

  // Constructor - set storage address
  function TestTokenApprove(address _storage) public {
    app_storage = _storage;
  }

  // Change storage address
  function newStorage(address _new_storage) public {
    app_storage = _new_storage;
  }

  // Get the last chunk of data stored with getBuffer
  function getLastStorage() public view returns (bytes32[] stored) {
    return last_storage_event;
  }

  /// TOKEN STORAGE ///

  // Storage seed for user allowances mapping
  bytes32 public constant TOKEN_ALLOWANCES = keccak256("token_allowances");

  /// FUNCTION SELECTORS ///

  // Function selector for storage "read"
  // read(bytes32 _exec_id, bytes32 _location) view returns (bytes32 data_read);
  bytes4 public constant RD_SING = bytes4(keccak256("read(bytes32,bytes32)"));

  /// EXCEPTION MESSAGES ///

  bytes32 public constant ERR_UNKNOWN_CONTEXT = bytes32("UnknownContext"); // Malformed '_context' array
  bytes32 public constant ERR_READ_FAILED = bytes32("StorageReadFailed"); // Read from storage address failed

  /*
  Approves another address to spend tokens on the sender's behalf

  @param _spender: The address for which the amount will be approved
  @param _amt: The amount of tokens to approve for spending
  @param _context: The execution context for this application - a 96-byte array containing (in order):
    1. Application execution id
    2. Original script sender (address, padded to 32 bytes)
    3. Wei amount sent with transaction to storage
  @return store_data: A formatted storage request - first 64 bytes designate a forwarding address (and amount) for any wei sent
  */
  function approve(address _spender, uint _amt, bytes _context) public
  returns (bytes32[] store_data) {
    // Ensure valid inputs
    require(_spender != address(0) && _amt != 0);
    if (_context.length != 96)
      triggerException(ERR_UNKNOWN_CONTEXT);

    address sender;
    bytes32 exec_id;
    // Parse context array and get sender address and execution id
    (exec_id, sender, ) = parse(_context);

    // Create storage return data buffer in memory
    uint ptr = stBuff();
    // Place payment destination and amount in buffer (0, 0)
    stPush(ptr, 0);
    stPush(ptr, 0);
    // Push spender allowance location to buffer
    stPush(ptr, keccak256(keccak256(_spender), keccak256(keccak256(sender), TOKEN_ALLOWANCES)));
    // Push new spender allowance to buffer
    stPush(ptr, bytes32(_amt));

    // Get bytes32[] representation of storage buffer
    store_data = getBuffer(ptr);
  }

  /*
  Increases the spending approval amount set by the sender for the _spender

  @param _spender: The address for which the allowance will be increased
  @param _amt: The amount to increase the allowance by
  @param _context: The execution context for this application - a 96-byte array containing (in order):
    1. Application execution id
    2. Original script sender (address, padded to 32 bytes)
    3. Wei amount sent with transaction to storage
  @return store_data: A formatted storage request - first 64 bytes designate a forwarding address (and amount) for any wei sent
  */
  function increaseApproval(address _spender, uint _amt, bytes _context) public returns (bytes32[] store_data) {
    // Ensure valid inputs
    require(_spender != address(0) && _amt != 0);
    if (_context.length != 96)
      triggerException(ERR_UNKNOWN_CONTEXT);

    address sender;
    bytes32 exec_id;
    // Parse context array and get sender address and execution id
    (exec_id, sender, ) = parse(_context);

    // Create 'read' calldata buffer in memory
    uint ptr = cdBuff(RD_SING);
    // Push exec id and spender allowance location to buffer
    cdPush(ptr, exec_id);
    cdPush(ptr, keccak256(keccak256(_spender), keccak256(keccak256(sender), TOKEN_ALLOWANCES)));

    // Read spender allowance from storage
    uint spender_bal = uint(readSingle(ptr));
    // Safely increase the spender's balance -
    require(spender_bal + _amt > spender_bal);
    spender_bal += _amt;

    // Overwrite previous buffer, and create storage return buffer
    stOverwrite(ptr);
    // Place payment destination and amount in buffer (0, 0)
    stPush(ptr, 0);
    stPush(ptr, 0);
    // Place spender allowance location and updated allowance in buffer
    stPush(ptr, keccak256(keccak256(_spender), keccak256(keccak256(sender), TOKEN_ALLOWANCES)));
    stPush(ptr, bytes32(spender_bal));

    // Get bytes32[] representation of storage buffer
    store_data = getBuffer(ptr);
  }

  /*
  Decreases the spending approval amount set by the sender for the _spender

  @param _spender: The address for which the allowance will be increased
  @param _amt: The amount to decrease the allowance by
  @param _context: The execution context for this application - a 96-byte array containing (in order):
    1. Application execution id
    2. Original script sender (address, padded to 32 bytes)
    3. Wei amount sent with transaction to storage
  @return store_data: A formatted storage request - first 64 bytes designate a forwarding address (and amount) for any wei sent
  */
  function decreaseApproval(address _spender, uint _amt, bytes _context) public returns (bytes32[] store_data) {
    // Ensure valid inputs
    require(_spender != address(0) && _amt != 0);
    if (_context.length != 96)
      triggerException(ERR_UNKNOWN_CONTEXT);

    address sender;
    bytes32 exec_id;
    // Parse context array and get sender address and execution id
    (exec_id, sender, ) = parse(_context);

    // Create 'read' calldata buffer in memory
    uint ptr = cdBuff(RD_SING);
    // Push exec id and spender allowance location to buffer
    cdPush(ptr, exec_id);
    cdPush(ptr, keccak256(keccak256(_spender), keccak256(keccak256(sender), TOKEN_ALLOWANCES)));

    // Read spender allowance from storage
    uint spender_bal = uint(readSingle(ptr));
    // Safely decrease the spender's balance -
    spender_bal = (_amt > spender_bal ? 0 : spender_bal - _amt);

    // Overwrite previous buffer, and create storage return buffer
    stOverwrite(ptr);
    // Place payment destination and amount in buffer (0, 0)
    stPush(ptr, 0);
    stPush(ptr, 0);
    // Place spender allowance location and updated allowance in buffer
    stPush(ptr, keccak256(keccak256(_spender), keccak256(keccak256(sender), TOKEN_ALLOWANCES)));
    stPush(ptr, bytes32(spender_bal));

    // Get bytes32[] representation of storage buffer
    store_data = getBuffer(ptr);
  }

  /*
  Creates a buffer for return data storage. Buffer pointer stores the lngth of the buffer

  @return ptr: The location in memory where the length of the buffer is stored - elements stored consecutively after this location
  */
  function stBuff() internal pure returns (uint ptr) {
    assembly {
      // Get buffer location - free memory
      ptr := mload(0x40)
      // Update free-memory pointer - it's important to note that this is not actually free memory, if the pointer is meant to expand
      mstore(0x40, add(0x20, ptr))
    }
  }

  /*
  Creates a new return data storage buffer at the position given by the pointer. Does not update free memory

  @param _ptr: A pointer to the location where the buffer will be created
  */
  function stOverwrite(uint _ptr) internal pure {
    assembly {
      // Simple set the initial length - 0
      mstore(_ptr, 0)
    }
  }

  /*
  Pushes a value to the end of a storage return buffer, and updates the length

  @param _ptr: A pointer to the start of the buffer
  @param _val: The value to push to the buffer
  */
  function stPush(uint _ptr, bytes32 _val) internal pure {
    assembly {
      // Get end of buffer - 32 bytes plus the length stored at the pointer
      let len := add(0x20, mload(_ptr))
      // Push value to end of buffer (overwrites memory - be careful!)
      mstore(add(_ptr, len), _val)
      // Increment buffer length
      mstore(_ptr, len)
      // If the free-memory pointer does not point beyond the buffer's current size, update it
      if lt(mload(0x40), add(add(0x20, _ptr), len)) {
        mstore(0x40, add(add(0x40, _ptr), len)) // Ensure free memory pointer points to the beginning of a memory slot
      }
    }
  }

  /*
  Returns the bytes32[] stored at the buffer

  @param _ptr: A pointer to the location in memory where the calldata for the call is stored
  @return store_data: The return values, which will be stored
  */
  function getBuffer(uint _ptr) internal returns (bytes32[] store_data){
    assembly {
      // If the size stored at the pointer is not evenly divislble into 32-byte segments, this was improperly constructed
      if gt(mod(mload(_ptr), 0x20), 0) { revert (0, 0) }
      mstore(_ptr, div(mload(_ptr), 0x20))
      store_data := _ptr
    }
    last_storage_event = store_data;
  }

  /*
  Creates a calldata buffer in memory with the given function selector

  @param _selector: The function selector to push to the first location in the buffer
  @return ptr: The location in memory where the length of the buffer is stored - elements stored consecutively after this location
  */
  function cdBuff(bytes4 _selector) internal pure returns (uint ptr) {
    assembly {
      // Get buffer location - free memory
      ptr := mload(0x40)
      // Place initial length (4 bytes) in buffer
      mstore(ptr, 0x04)
      // Place function selector in buffer, after length
      mstore(add(0x20, ptr), _selector)
      // Update free-memory pointer - it's important to note that this is not actually free memory, if the pointer is meant to expand
      mstore(0x40, add(0x40, ptr))
    }
  }

  /*
  Pushes a value to the end of a calldata buffer, and updates the length

  @param _ptr: A pointer to the start of the buffer
  @param _val: The value to push to the buffer
  */
  function cdPush(uint _ptr, bytes32 _val) internal pure {
    assembly {
      // Get end of buffer - 32 bytes plus the length stored at the pointer
      let len := add(0x20, mload(_ptr))
      // Push value to end of buffer (overwrites memory - be careful!)
      mstore(add(_ptr, len), _val)
      // Increment buffer length
      mstore(_ptr, len)
      // If the free-memory pointer does not point beyond the buffer's current size, update it
      if lt(mload(0x40), add(add(0x20, _ptr), len)) {
        mstore(0x40, add(add(0x2c, _ptr), len)) // Ensure free memory pointer points to the beginning of a memory slot
      }
    }
  }

  /*
  Executes a 'readMulti' function call, given a pointer to a calldata buffer
  Test version reads from app storage address

  @param _ptr: A pointer to the location in memory where the calldata for the call is stored
  @return read_values: The values read from storage
  */
  function readMulti(uint _ptr) internal view returns (bytes32[] read_values) {
    bool success;
    address _storage = app_storage;
    assembly {
      // Minimum length for 'readMulti' - 1 location is 0x84
      if lt(mload(_ptr), 0x84) { revert (0, 0) }
      // Read from storage
      success := staticcall(gas, _storage, add(0x20, _ptr), mload(_ptr), 0, 0)
      // If call succeed, get return information
      if gt(success, 0) {
        // Ensure data will not be copied beyond the pointer
        if gt(sub(returndatasize, 0x20), mload(_ptr)) { revert (0, 0) }
        // Copy returned data to pointer, overwriting it in the process
        // Copies returndatasize, but ignores the initial read offset so that the bytes32[] returned in the read is sitting directly at the pointer
        returndatacopy(_ptr, 0x20, sub(returndatasize, 0x20))
        // Set return bytes32[] to pointer, which should now have the stored length of the returned array
        read_values := _ptr
      }
    }
    if (!success)
      triggerException(ERR_READ_FAILED);
  }

  /*
  Executes a 'read' function call, given a pointer to a calldata buffer
  Test version reads from app storage address

  @param _ptr: A pointer to the location in memory where the calldata for the call is stored
  @return read_value: The value read from storage
  */
  function readSingle(uint _ptr) internal view returns (bytes32 read_value) {
    bool success;
    address _storage = app_storage;
    assembly {
      // Length for 'read' buffer must be 0x44
      if iszero(eq(mload(_ptr), 0x44)) { revert (0, 0) }
      // Read from storage, and store return to pointer
      success := staticcall(gas, _storage, add(0x20, _ptr), mload(_ptr), _ptr, 0x20)
      // If call succeeded, store return at pointer
      if gt(success, 0) { read_value := mload(_ptr) }
    }
    if (!success)
      triggerException(ERR_READ_FAILED);
  }

  /*
  Reverts state changes, but passes message back to caller

  @param _message: The message to return to the caller
  */
  function triggerException(bytes32 _message) internal pure {
    assembly {
      mstore(0, _message)
      revert(0, 0x20)
    }
  }

  // Parses context array and returns execution id, sender address, and sent wei amount
  function parse(bytes _context) internal pure returns (bytes32 exec_id, address from, uint wei_sent) {
    assembly {
      exec_id := mload(add(0x20, _context))
      from := mload(add(0x40, _context))
      wei_sent := mload(add(0x60, _context))
    }
    // Ensure sender and exec id are valid
    if (from == address(0) || exec_id == bytes32(0))
      triggerException(ERR_UNKNOWN_CONTEXT);
  }
}