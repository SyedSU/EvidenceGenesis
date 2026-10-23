/* Compile as one TU to verify the private digest/UTF8 implementation without
   adding test-only production exports or trusting a fake GGUF as inference. */
#include "../native/inference/inference_core.cpp"
#include <cassert>
int main() {
  Sha256 empty;
  assert(empty.finish() ==
         "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  Sha256 abc;
  abc.add("a", 1);
  abc.add("bc", 2);
  assert(abc.finish() ==
         "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  Sha256 million;
  for (int i = 0; i < 1000000; i++)
    million.add("a", 1);
  assert(million.finish() ==
         "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
  std::atomic<bool> canceled{false};
  std::unique_ptr<FILE,FileCloser> original(std::tmpfile());
  assert(original);assert(std::fwrite("abc",1,3,original.get())==3);std::rewind(original.get());
  std::string digest;
  auto snapshot=verified_snapshot(original.get(),std::filesystem::temp_directory_path().string()+"/source.gguf",canceled,digest);
  assert(snapshot && digest=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  std::rewind(original.get());assert(std::fwrite("xyz",1,3,original.get())==3);std::fflush(original.get());
  char copied[3];assert(std::fread(copied,1,3,snapshot.get())==3 && std::memcmp(copied,"abc",3)==0);
  canceled=true;
  auto refused=verified_snapshot(original.get(),std::filesystem::temp_directory_path().string()+"/source.gguf",canceled,digest);
  assert(!refused);
  assert(utf8("hello\xf0\x9f\x8c\xb2"));
  assert(!utf8("\xf0\x9f\x8c"));
  assert(!utf8("\xc0\x80"));
  assert(!utf8("\xed\xa0\x80"));
  assert(!utf8(std::string("x\0y", 3)));
}
