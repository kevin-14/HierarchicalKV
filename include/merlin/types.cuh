/*
 * Copyright (c) 2022, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once

#include <stddef.h>
#include <cuda/std/semaphore>

namespace nv {
namespace merlin {

template <class M>
struct Meta {
  M val;
};

constexpr uint64_t EMPTY_KEY = 0xFFFFFFFFFFFFFFFF;
constexpr uint64_t MAX_META = 0xFFFFFFFFFFFFFFFF;
constexpr uint64_t EMPTY_META = 0lu;

template <class K, class V, class M, size_t DIM>
struct Bucket {
  K* keys;         // HBM
  Meta<M>* metas;  // HBM
  V* cache;        // HBM(optional)
  V* vectors;      // Pinned memory or HBM

  /* For upsert_kernel without user specified metas
     recording the current meta, the cur_meta will
     increment by 1 when a new inserting happens. */
  M cur_meta;

  /* min_meta and min_pos is for or upsert_kernel
     with user specified meta. They record the minimum
     meta and its pos in the bucket. */
  M min_meta;
  int min_pos;
};

using Mutex = cuda::binary_semaphore<cuda::thread_scope_device>;

template <class K, class V, class M, size_t DIM>
struct Table {
  Bucket<K, V, M, DIM>* buckets;
  Mutex* locks;                 // mutex for write buckets
  int* buckets_size;            // size of each buckets.
  V** slices;                   // Handles of the HBM/ HMEM slices.
  size_t bytes_per_slice;       // Size by byte of one slice.
  size_t num_of_memory_slices;  // Number of vectors memory slices.
  size_t capacity = 134217728;  // Initial capacity.
  size_t max_size =
      std::numeric_limits<uint64_t>::max();  // Up limit of the table capacity.
  size_t buckets_num;                        // Number of the buckets.
  size_t bucket_max_size = 128;              // Volume of each buckets.
  size_t max_hbm_for_vectors = 0;            // Max HBM allocated for vectors
  size_t remaining_hbm_for_vectors = 0;  // Remaining HBM allocated for vectors
  bool is_pure_hbm = true;               // unused
  bool primary = true;                   // unused
  int slots_offset = 0;                  // unused
  int slots_number = 0;                  // unused
  int device_id = 0;                     // Device id
  int tile_size;
};

template <class K, class M>
using EraseIfPredictInternal =
    bool (*)(const K& key,       ///< iterated key in table
             M& meta,            ///< iterated meta in table
             const K& pattern,   ///< input key from caller
             const M& threshold  ///< input meta from caller
    );

/**
 * An abstract class provides interface between the nv::merlin::HashTable
 * and a file, which enables the table to save to the file or load from
 * the file, by overriding the `read` and `write` method.
 *
 * @tparam K The data type of the key.
 * @tparam V The data type of the vector's elements.
 *         The item data type should be a basic data type of C++/CUDA.
 * @tparam M The data type for `meta`.
 *           The currently supported data type is only `uint64_t`.
 * @tparam D The dimension of the vectors.
 *
 */
template <class K, class V, class M, size_t D>
class BaseKVFile {
 public:
  virtual ~BaseKVFile() {}

  /**
   * Read from file and fill into the keys, values, and metas buffer.
   * When calling save/load method from table, it can assume that the
   * received buffer of keys, vectors, and metas are automatically
   * pre-allocated.
   *
   * @param n The number of KV pairs expect to read. `int64_t` was used
   *          here to adapt to various filesytem and formats.
   * @param keys The pointer to received buffer for keys.
   * @param vectors The pointer to received buffer for vectors.
   * @param metas The pointer to received buffer for metas.
   *
   * @return Number of KV pairs have been successfully read.
   */
  virtual size_t read(size_t n, K* keys, V* vectors, M* metas) = 0;

  /**
   * Write keys, values, metas from table to the file. It defines
   * an abstract method to get batch of KV pairs and write them into
   * file.
   *
   * @param n The number of KV pairs to be written. `int64_t` was used
   *          here to adapt to various filesytem and formats.
   * @param keys The keys will be written to file.
   * @param vectors The vectors of values will be written to file.
   * @param metas The metas will be written to file.
   *
   * @return Number of KV pairs have been successfully written.
   */
  virtual size_t write(size_t n, const K* keys, const V* vectors,
                       const M* metas) = 0;
};

}  // namespace merlin
}  // namespace nv
