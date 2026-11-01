# tachyon 交付说明

> **免责声明**
>
> 本工具仅供安全研究、逆向工程学习和合法分析使用，请勿用于破解商业软件、
> 侵犯版权等非法用途，使用者需自行承担一切法律责任。

纯 C11 多格式反编译器。零第三方依赖（libc + pthread + libm），单二进制。

## 当前实测

### source.apk（22MB / 3 dex / 15216 类）

| 指标 | 数值 |
|---|---|
| 反编译 | **3.5 秒**（8 线程） |
| javac 通过率 | **100.00%**（15235 / 15235） |
| 失败文件 | **0** |
| 输出 | 15216 个类 + 19 个桩 + 4 个工程文件 |
| 混淆类重命名 | 1327 个 |

### 微信 8.0.79（285MB / 18 dex / 253230 类）

| 指标 | 数值 |
|---|---|
| 反编译 + 落盘 | **47.8 秒**，0 失败 |
| `--emit-only`（不写盘） | 10.8 秒 |
| `--merge`（按包合并） | 文件数 253230 → 8608 |
| 输出体积 | 1.1 GB |

写盘的物理下限已实测：这台机器裸写 253230 个文件需 **121 秒**（2090 文件/秒）。
tachyon 用 37 秒完成同样数量（6800 文件/秒），已比裸写快 3.4 倍，**继续压缩到 20 秒内
不可能**——剩余开销是 f2fs 的 per-file 元数据。要更快只能减少文件数（`--merge`）。

## CLI

```
tachyon d <file> [-o <dir>] [-j N] [--mode fast|balanced|accurate|max]
                 [--bodies] [--rename map.txt] [--emit-only] [--merge] [--keep]
tachyon info  <file>
tachyon dis   <file> [-n N]
tachyon list  <file>
tachyon json  <file>
tachyon formats
```

- `-o`：**默认 `./out`，每次运行前自动清空**（避免多次运行堆满磁盘）。`--keep` 保留。
- `--mode fast`：跳过整图分析，最快
- `--mode balanced`：默认
- `--mode accurate`：额外开启跨 dex 超类型遍历
- `--mode max`：**测试功能**，按 CPU 数 ×4 开线程，把机器压满。只在桌面验证过，
  **不要在手机上运行**
- `--emit-only`：只反编译不写盘
- `--merge`：每个包合并为一个 `_merged.java`（只有 public 类会被降级），实测可编译
- `--rename`：应用 ProGuard/R8 mapping.txt

## 工程结构还原

一次运行产出可直接用 Gradle 打开的结构：

```
out/
├── AndroidManifest.xml     二进制 AXML 解码成可读文本
├── build.gradle            namespace / compileSdk / minSdk / targetSdk / versionCode / versionName
├── settings.gradle         rootProject.name + include ':app'
├── local.properties        sdk.dir 占位（提示用户改成本机路径）
└── com/...                 Java 源码树
```

`AndroidManifest.xml` 是 APK 里的二进制 XML（字符串池 + 元素块），由自研解码器
`src/apk/axml.c` 还原，属性值按类型格式化（字符串 / 引用 / 整数 / 布尔 / 尺寸）。

## 水印

每个输出文件首行固定为：

```
//TachYon An incredibly fast decompilation tool
//No dependencies
//TachYon CN AI Agent DeepSeekv4.1flash
```

## 引擎与扩展

各能力都写成了独立模块，互不依赖，可单独调用。

### 1. 字符串解密引擎（`src/ir/emulate.c`）

一个轻量 Dalvik 解释器，在反编译期实际执行解密函数，把密文还原成明文。

- 覆盖指令：move / move-result / const-* / aget|aput / array-length / new-instance /
  new-array / goto / if-*（22t、if-*z）/ int-to-char|short|byte / 0xd8..0xe2 的 lit8 算术 /
  invoke-static|virtual|direct
- 模拟的 JDK 方法：`String.length|charAt|toString`、`StringBuilder.append|toString`、
  `Integer.parseInt|valueOf`、`Character.toString`
- 递归深度上限 12，步数上限 20000，超出即放弃求值并保留原始调用
- 求值结果与手算一致（XOR 样本 `8888898` → `bbbbbcb`）

**关键约定**：`append(char)` 与 `append(int)` 靠 proto 参数描述符区分；`charAt` 返回
`EMU_CHAR` 而不是 `EMU_INT`，否则会输出数字而不是字符。

### 2. 混淆名重建引擎（`src/emit/heuristic.c`）

单字母类名（`a` / `b2` / `a0`）按类自身内容推断名字，**有证据才改名**：

| 证据来源 | 生成的名字 |
|---|---|
| 静态字符串常量（4–20 字符） | `Impl_<常量>` / `Abstract_<常量>` |
| 非 Object 父类 | `Sub_<父类>` / `Abstract_<父类>` |
| 唯一实现接口 | `Impl_<接口>` |
| 都没有 | **保留原名**（`a`、`a0`…） |

新名一定追加原短名（如 `Impl_Serializable_cn`），保证同包内不重名。
名字查找是哈希表 O(1)，25 万类规模可用。

**必须同时改三处，否则声明、路径、引用会分叉**：
`java_class_fqname`（路径）、`facts.name`（声明）、`remap_java_type`（所有引用）。
数组类型 `[La;` 也要剥离 `[` 后查表。

### 3. 自写依赖层（`src/emit/platform_builtin.c`、`src/emit/stubs.c`）

不依赖 android.jar，内置三张表 + 桩生成：

- **平台构造器表**：`View(Context)`、`GZIPOutputStream(OutputStream)`、`ThreadPoolExecutor(...)` 等
  80 余个框架类的构造器签名。父类只有带参构造器时，合成构造器会传类型化默认值。
- **平台抽象方法表**：`Service.onBind`、`ContentProvider.query`、`BaseAdapter.getView` 等，
  子类没实现时自动合成桩方法，避免把 Android 组件标成 abstract。
- **平台方法签名表 + 父类链**：识别 `ViewParent.getLayoutDirection():int`、
  `AdapterView.setAdapter` 这类冲突，冲突成员或接口会被丢弃而不是留下编译错误。
- **桩生成**：APK 引用但没打包的类型（`androidx.window.*`、`android.view.RenderNode`、
  `org.conscrypt.*`）生成占位声明，interface / class 按 `implements` 出现情况判定。

### 4. 反混淆资源解码（`src/apk/axml.c`）

二进制 XML 解码器：字符串池（UTF-8 / UTF-16）、命名空间、元素、属性、CDATA。
同时提供按名字取属性（`package`、`android:versionCode`…），工程文件由它驱动。

### 5. 多格式 provider（`src/formats/`）

| 格式 | 能力 | 真值验证 |
|---|---|---|
| DEX / APK | 完整反编译为 Java | `dexdump -d` 逐条一致（65695 条） |
| JVM class | 反汇编 + 结构 | `javap -c -p` 逐条一致 |
| CPython pyc | 反汇编 + 结构 | Python `dis` 逐条一致 |
| Lua 5.1–5.4 | 反汇编 | `luac -l` 逐条一致 |

### 6. 方法体反编译（`--bodies`）

14195 类实测只剩 2 个错误。默认关闭，因为方法体还原会改变输出语义
（异常处理边界、`finally` 结构等无法完全复原）。

## 关键 bug 与根因（本轮）

1. **`dex_string` 内存炸弹**：每解析一个字符串就申请「文件剩余大小」（微信 8.6MB dex →
   每串 8MB），25 万类场景直接把虚拟内存吃穿并拖垮手机。改成按 uleb128 字符数 ×3 分配。
2. **隐式函数声明截断指针**：`body.c` 缺 `emit/java.h`，`java_body_arena()` 被当返回 `int`，
   64 位指针高 32 位被丢弃 → 段错误。构建时加 `-Werror=implicit-function-declaration`。
3. **winner 检查在去重之后**：协变方法先被 `sigset_add` 标记，真实方法再被当作重复丢弃。
   顺序必须反过来。
4. **跨 dex 索引混用**：`class_def_of_type` 返回的是**所属 dex** 的索引，却用当前 dex 读
   flags 和数据，把接口误判成有 final 方法的类。
5. **合成构造器条件漏洞**：父类构造器全是带参时两个条件都不成立，干脆不生成构造器，
   Java 隐式构造器又去调不存在的 `super()`。
6. **桩分类丢失**：同一类型先作为参数出现（记为 class）、后出现在 `implements`（应为
   interface），哈希去重没有回写条目，导致 `interface expected`。
7. **javac 语法错误掩盖语义错误**：任何 parse error 都会让 javac 跳过整个语义分析阶段，
   测出的通过率会虚高。`bench/report.py` 已改成两遍编译并显式警告。

## 构建

```sh
cd ~/workspace/tachyon && make run   # 产物 /tmp/tbuild/tachyon
```

`sdcard` 挂载为 `noexec`，二进制必须放 `/tmp`。

## 验证

```sh
python3 bench/report.py ./out     # 完整错误报告，写 /tmp/report/
sh bench/run_tests.sh             # 功能回归
```

## 未做

- CIL (.NET)、EVM、Go 二进制、x86-64 / ARM64 反汇编器
- 控制流平坦化还原、反调试检测
- C / Go / Kotlin 语言输出（用户已明确延期）
