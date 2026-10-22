// IEEE CRC-32, reflected 0xedb88320, little-endian bytes in a 32-bit word.
// Caller starts with ffffffff and complements the final state (zlib convention).
function [31:0] crc32_word;
    input [31:0] crc,data;
    integer bit_index;
    reg [31:0] value;
    begin
        value=crc^data;
        for(bit_index=0;bit_index<32;bit_index=bit_index+1)
            value=value[0] ? ((value>>1)^32'hedb88320) : (value>>1);
        crc32_word=value;
    end
endfunction
