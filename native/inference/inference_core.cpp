/* First-party bounded CPU inference worker. No network, tools, or subprocesses.
 */
#include "inference_core.h"
#include "llama.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
#include <unistd.h>

namespace {
constexpr const char *model_hash =
    "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db";
constexpr size_t max_input = 40000, max_output = 20000;
constexpr int context_size = 2048, max_tokens = 512, batch_size = 128;
/* SHA256, FIPS180-4. Streaming keeps model verification memory bounded. */
class Sha256 {
  uint32_t h[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                   0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  uint8_t block[64] = {};
  size_t used = 0;
  uint64_t bytes = 0;
  static uint32_t r(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }
  void compress() {
    static constexpr uint32_t k[64] = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
        0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
        0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
        0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
        0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};
    uint32_t w[64];
    for (int i = 0; i < 16; i++)
      w[i] = (uint32_t(block[4 * i]) << 24) |
             (uint32_t(block[4 * i + 1]) << 16) |
             (uint32_t(block[4 * i + 2]) << 8) | block[4 * i + 3];
    for (int i = 16; i < 64; i++)
      w[i] = w[i - 16] +
             (r(w[i - 15], 7) ^ r(w[i - 15], 18) ^ (w[i - 15] >> 3)) +
             w[i - 7] + (r(w[i - 2], 17) ^ r(w[i - 2], 19) ^ (w[i - 2] >> 10));
    uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5],
             g = h[6], v = h[7];
    for (int i = 0; i < 64; i++) {
      uint32_t t = v + (r(e, 6) ^ r(e, 11) ^ r(e, 25)) + ((e & f) ^ (~e & g)) +
                   k[i] + w[i];
      uint32_t u =
          (r(a, 2) ^ r(a, 13) ^ r(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
      v = g;
      g = f;
      f = e;
      e = d + t;
      d = c;
      c = b;
      b = a;
      a = t + u;
    }
    h[0] += a;
    h[1] += b;
    h[2] += c;
    h[3] += d;
    h[4] += e;
    h[5] += f;
    h[6] += g;
    h[7] += v;
  }

public:
  void add(const char *p, size_t n) {
    bytes += n;
    while (n--) {
      block[used++] = uint8_t(*p++);
      if (used == 64) {
        compress();
        used = 0;
      }
    }
  }
  std::string finish() {
    uint64_t bits = bytes * 8;
    block[used++] = 0x80;
    if (used > 56) {
      while (used < 64)
        block[used++] = 0;
      compress();
      used = 0;
    }
    while (used < 56)
      block[used++] = 0;
    for (int i = 7; i >= 0; i--)
      block[used++] = uint8_t(bits >> (8 * i));
    compress();
    std::string s;
    const char *hex = "0123456789abcdef";
    for (auto x : h)
      for (int i = 7; i >= 0; i--)
        s += hex[(x >> (i * 4)) & 15];
    return s;
  }
};
bool utf8(const std::string &s) {
  size_t i = 0;
  while (i < s.size()) {
    uint32_t c = uint8_t(s[i++]);
    if (c < 128) {
      if (c == 0)
        return false;
      continue;
    }
    int n;
    uint32_t minimum;
    if (c >= 0xc2 && c <= 0xdf) {
      n = 1;
      minimum = 0x80;
      c &= 31;
    } else if (c >= 0xe0 && c <= 0xef) {
      n = 2;
      minimum = 0x800;
      c &= 15;
    } else if (c >= 0xf0 && c <= 0xf4) {
      n = 3;
      minimum = 0x10000;
      c &= 7;
    } else
      return false;
    if (i + n > s.size())
      return false;
    while (n--) {
      uint8_t b = s[i++];
      if ((b & 0xc0) != 0x80)
        return false;
      c = (c << 6) | (b & 63);
    }
    if (c < minimum || c > 0x10ffff || (c >= 0xd800 && c <= 0xdfff))
      return false;
  }
  return true;
}
std::string quoted(const std::string &s) {
  std::string out = "\"";
  for (unsigned char c : s) {
    if (c == '"' || c == '\\') {
      out += '\\';
      out += char(c);
    } else if (c < 32) {
      const char *hex = "0123456789abcdef";
      out += "\\u00";
      out += hex[c >> 4];
      out += hex[c & 15];
    } else
      out += char(c);
  }
  return out + '"';
}
struct Result {
  std::string state = "idle", id, content, error;
  bool truncated = false;
};
std::string json(const Result &r) {
  return "{\"state\":" + quoted(r.state) + ",\"request_id\":" + quoted(r.id) +
         ",\"content\":" + quoted(r.content) + ",\"error\":" + quoted(r.error) +
         ",\"truncated\":" + (r.truncated ? "true" : "false") + "}";
}
struct FileCloser {
  void operator()(FILE *file) const { std::fclose(file); }
};
/* Copy to an unlinked app-private file before verification. Loading reads this
   exact snapshot, so mutation/replacement of the provisioned source cannot alter
   bytes after their hash was accepted. Peak temporary disk is one model copy. */
std::unique_ptr<FILE, FileCloser> verified_snapshot(FILE *source,
    const std::string &path, const std::atomic<bool> &canceled, std::string &digest) {
  digest.clear();
  if(canceled)return {};
  auto pattern=(std::filesystem::path(path).parent_path()/".genesis-model-XXXXXX").string();
  std::vector<char> name(pattern.begin(),pattern.end());name.push_back(0);
  int descriptor=mkstemp(name.data());
  if(descriptor<0)throw std::runtime_error("Private model snapshot unavailable; check free space and folder permissions.");
  if(unlink(name.data())!=0){close(descriptor);std::remove(name.data());throw std::runtime_error("Private model snapshot could not be unlinked.");}
  FILE *opened=fdopen(descriptor,"w+b");
  if(!opened){close(descriptor);throw std::runtime_error("Private model snapshot could not open.");}
  std::unique_ptr<FILE,FileCloser> snapshot(opened);
  Sha256 hash;std::array<char,65536> buffer;size_t count;uint64_t size=0;
  while(!canceled && (count=std::fread(buffer.data(),1,buffer.size(),source))>0){
    size+=count;
    if(size>1024ULL*1024*1024)throw std::runtime_error("Model exceeds reviewed size bound.");
    if(std::fwrite(buffer.data(),1,count,snapshot.get())!=count)throw std::runtime_error("Private model snapshot write failed; check free space.");
    hash.add(buffer.data(),count);
  }
  if(canceled)return {};
  if(std::ferror(source) || std::fflush(snapshot.get())!=0 || std::fseek(snapshot.get(),0,SEEK_SET)!=0)
    throw std::runtime_error("Private model snapshot could not be verified.");
  digest=hash.finish();return snapshot;
}
class Engine {
  std::mutex api, mutex;
  std::thread worker;
  std::atomic<bool> canceled{false};
  bool running = false;
  llama_model *model = nullptr;
  llama_context *context = nullptr;
  Result result;
  static bool progress(float, void *p) {
    return !static_cast<Engine *>(p)->canceled.load();
  }
  static bool abort(void *p) {
    return static_cast<Engine *>(p)->canceled.load();
  }
  void release() {
    if (context)
      llama_free(context);
    if (model)
      llama_model_free(model);
    context = nullptr;
    model = nullptr;
  }
  void complete(Result r) {
    std::lock_guard<std::mutex> lock(mutex);
    if (canceled) {
      r.state = "canceled";
      r.error = "Canceled; notes retained.";
      r.content.clear();
      r.truncated = false;
    }
    result = std::move(r);
    running = false;
  }
  void load(std::string path) {
    Result r;
    r.state = "ready";
    try {
      release();
      std::unique_ptr<FILE, FileCloser> file(std::fopen(path.c_str(), "rb"));
      if (!file)
        throw std::runtime_error("Model file unavailable.");
      std::string digest;
      auto snapshot=verified_snapshot(file.get(),path,canceled,digest);
      if(canceled){complete(r);return;}
      if(digest!=model_hash)throw std::runtime_error("Model hash differs from reviewed SHA256.");
      auto params = llama_model_default_params();
      params.n_gpu_layers = 0;
      params.progress_callback = progress;
      params.progress_callback_user_data = this;
      /* Copy tensors into owned memory: avoid later file mutation via mmap. */
      params.load_mode = LLAMA_LOAD_MODE_NONE;
      model = llama_model_load_from_file_ptr(snapshot.get(), params);
      if (!model)
        throw std::runtime_error("Reviewed model could not load.");
      auto cp = llama_context_default_params();
      cp.n_ctx = context_size;
      cp.n_batch = batch_size;
      cp.n_ubatch = batch_size;
      cp.n_threads = 2;
      cp.n_threads_batch = 2;
      cp.abort_callback = abort;
      cp.abort_callback_data = this;
      cp.no_perf = true;
      context = llama_init_from_model(model, cp);
      if (!context)
        throw std::runtime_error("Model context allocation failed.");
      if (canceled)
        release();
    } catch (const std::exception &e) {
      release();
      r.state = "error";
      r.error = e.what();
    } catch (...) {
      release();
      r.state = "error";
      r.error = "Native model load failed.";
    }
    complete(r);
  }
  void generate(std::string system, std::string user, std::string id) {
    Result r;
    r.state = "completed";
    r.id = std::move(id);
    llama_sampler *sampler = nullptr;
    try {
      llama_memory_clear(llama_get_memory(context), true);
      const char *tmpl = llama_model_chat_template(model, nullptr);
      if (!tmpl)
        throw std::runtime_error("Model chat template missing.");
      llama_chat_message messages[2] = {{"system", system.c_str()},
                                        {"user", user.c_str()}};
      std::vector<char> prompt(2 * (system.size() + user.size()) + 1024);
      int count = llama_chat_apply_template(tmpl, messages, 2, true,
                                            prompt.data(), int(prompt.size()));
      if (count < 0 || count > int(prompt.size()))
        throw std::runtime_error(
            "Model chat template unsupported or oversized.");
      auto vocab = llama_model_get_vocab(model);
      std::vector<llama_token> tokens(context_size);
      int n = llama_tokenize(vocab, prompt.data(), count, tokens.data(),
                             int(tokens.size()), true, true);
      if (n <= 0 || n + max_tokens > context_size)
        throw std::runtime_error(
            "Notes exceed local AI context; shorten them.");
      for (int offset = 0; offset < n && !canceled; offset += batch_size) {
        auto batch = llama_batch_get_one(tokens.data() + offset,
                                         std::min(batch_size, n - offset));
        if (llama_decode(context, batch) != 0)
          throw std::runtime_error("Prompt processing failed or canceled.");
      }
      sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
      if (!sampler)
        throw std::runtime_error("Sampler allocation failed.");
      llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
      for (int i = 0; i < max_tokens && !canceled; i++) {
        llama_token token = llama_sampler_sample(sampler, context, -1);
        if (llama_vocab_is_eog(vocab, token))
          break;
        std::vector<char> piece(256);
        int size = llama_token_to_piece(vocab, token, piece.data(),
                                        int(piece.size()), 0, false);
        if (size < 0) {
          piece.resize(size_t(-size));
          size = llama_token_to_piece(vocab, token, piece.data(),
                                      int(piece.size()), 0, false);
        }
        if (size < 0)
          throw std::runtime_error("Token decoding failed.");
        if (r.content.size() + size_t(size) > max_output) {
          r.truncated = true;
          break;
        }
        r.content.append(piece.data(), size_t(size));
        if (i == max_tokens - 1) {
          r.truncated = true;
          break;
        }
        auto batch = llama_batch_get_one(&token, 1);
        if (llama_decode(context, batch) != 0)
          throw std::runtime_error("Generation failed or canceled.");
      }
      /* Token pieces may split UTF8: retain only a complete valid ending. */
      for (int i = 0; i < 3 && !utf8(r.content) && !r.content.empty(); i++)
        r.content.pop_back();
      if (!canceled && (!utf8(r.content) || r.content.empty()))
        throw std::runtime_error("AI returned empty or invalid text.");
    } catch (const std::exception &e) {
      r.state = "error";
      r.error = e.what();
      r.content.clear();
    } catch (...) {
      r.state = "error";
      r.error = "Native generation failed.";
      r.content.clear();
    }
    if (sampler)
      llama_sampler_free(sampler);
    complete(r);
  }

public:
  Engine() { llama_backend_init(); }
  ~Engine() {
    stop();
    llama_backend_free();
  }
  void stop() {
    canceled = true;
    if (worker.joinable())
      worker.join();
    release();
    std::lock_guard<std::mutex> lock(mutex);
    running = false;
    result = Result{};
  }
  std::string call(const std::string &op, const std::string &a,
                   const std::string &b, const std::string &c) {
    std::lock_guard<std::mutex> gate(api);
    if (op == "shutdown") {
      stop();
      return json(Result{});
    }
    std::unique_lock<std::mutex> lock(mutex);
    auto error = [](const char *text) {
      Result r;
      r.state = "error";
      r.error = text;
      return json(r);
    };
    if (op == "poll") {
      auto answer = json(result);
      if (!running &&
          (result.state == "completed" || result.state == "canceled")) {
        result = Result{};
        result.state = context ? "ready" : "idle";
      }
      return answer;
    }
    if (op == "cancel") {
      if (running) {
        canceled = true;
        result.state = "canceling";
      }
      return json(result);
    }
    if (op != "load" && op != "generate")
      return error("Unknown native AI operation.");
    if (running)
      return error("A local AI operation is already running.");
    if (op == "load" && (a.empty() || a.size() > 32768 ||
                         !std::filesystem::path(a).is_absolute()))
      return error("Model requires an absolute private filesystem path.");
    if (op == "generate" && (!context || a.empty() || b.empty() || c.empty() ||
                             c.size() > 80 || a.size() + b.size() > max_input))
      return error("AI is unavailable or request is invalid/oversized.");
    lock.unlock();
    if (worker.joinable())
      worker.join();
    lock.lock();
    canceled = false;
    result = Result{};
    result.state = op == "load" ? "loading" : "generating";
    result.id = op == "generate" ? c : "";
    running = true;
    try {
      if (op == "load")
        worker = std::thread(&Engine::load, this, a);
      else
        worker = std::thread(&Engine::generate, this, a, b, c);
    } catch (...) {
      running = false;
      result.state = "error";
      result.error = "Could not start native AI worker.";
    }
    return json(result);
  }
};
} // namespace
extern "C" AI_EXPORT const char *genesis_ai_request(const char *op,
                                                    const char *a,
                                                    const char *b,
                                                    const char *c) {
  static Engine engine;
  thread_local std::string answer;
  try {
    const char *args[] = {op, a, b, c};
    for (auto p : args) {
      if (!p || strnlen(p, max_input + 1) > max_input || !utf8(p)) {
        Result r;
        r.state = "error";
        r.error = "Invalid or oversized UTF8 argument.";
        answer = json(r);
        return answer.c_str();
      }
    }
    answer = engine.call(op, a, b, c);
  } catch (...) {
    answer = "{\"state\":\"error\",\"request_id\":\"\",\"content\":\"\","
             "\"error\":\"Native AI call failed.\"}";
  }
  return answer.c_str();
}
