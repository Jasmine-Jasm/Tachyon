# tachyon

纯 C11 编写的多格式反编译器。零第三方依赖，单二进制，可直接嵌入。

```
source.apk（15216 类）        3.5 秒      javac 通过率 100.00%
微信 8.0.79（253230 类）     47.8 秒      0 失败
```

> **免责声明**
>
> 本工具仅供安全研究、逆向工程学习和合法分析使用，请勿用于破解商业软件、
> 侵犯版权等非法用途，使用者需自行承担一切法律责任。

## 快速开始

```sh
# 构建。工作区挂载为 noexec，产物落在 /tmp。
make run

# 反编译，输出到 ./out（每次运行前自动清空）
/tmp/tbuild/tachyon d app.apk

# 带机器可读进度（见「调用接口」）
/tmp/tbuild/tachyon d app.apk --progress

# 类很多时用合并模式：每包一个文件，仍可编译
/tmp/tbuild/tachyon d app.apk --merge
```

输出是一套能直接用 Gradle 打开的工程：

```
out/
├── AndroidManifest.xml     二进制 AXML 解码成文本
├── build.gradle            namespace / compileSdk / minSdk / targetSdk / 版本号
├── settings.gradle
├── local.properties
├── <包路径>/<类名>.java
└── <缺失依赖>/...           为 APK 引用但未打包的库生成的桩声明
```

## 嵌入到别的项目

`libs/arm64-v8a/libtachyon.so` 是预编译好的 AArch64 **静态**可执行文件
（1.4 MB，零动态依赖），丢进 `jniLibs/` 就能用。完整调用接口——命令行参数、
`#PROGRESS` 进度协议、退出码、Java / Python / C 三种调用示例，以及 Android 上
的 SELinux 注意事项——都在 [libs/README.md](libs/README.md)。

各引擎模块也可以单独编进别的程序，头文件即接口，模块之间互不依赖。

## CLI

```
tachyon d <file> [-o <dir>] [-j N] [--progress]
                 [--mode fast|balanced|accurate|max]
                 [--bodies] [--merge] [--keep] [--emit-only] [--rename map.txt]
tachyon info  <file>     dex 数量与各表计数
tachyon dis   <file>     反汇编
tachyon list  <file>     列出压缩包条目
tachyon json  <file>     结构导出为 JSON
tachyon formats          支持的格式
```

`--mode max` 是**测试功能**：按 CPU 数 ×4 开线程把机器压满，只在桌面验证过，
手机上不要开。

## 支持的格式

| 格式 | 能力 | 真值验证 |
|---|---|---|
| DEX / APK | 完整反编译为 Java | 与 `dexdump -d` 逐条一致（65695 条指令） |
| JVM class | 反汇编 + 结构 | 与 `javap -c -p` 逐条一致 |
| CPython pyc | 反汇编 + 结构 | 与 Python `dis` 逐条一致 |
| Lua 5.1–5.4 | 反汇编 | 与 `luac -l` 逐条一致 |

## 引擎

每个模块自成一体，可以单独使用。

| 模块 | 作用 |
|---|---|
| `src/dex/dex.c` | DEX 解析：字符串池（MUTF-8）、类型、原型、类数据、字节码 |
| `src/ir/emulate.c` | Dalvik 解释器；反编译期求值字符串解密函数，把密文还原成明文 |
| `src/emit/heuristic.c` | 混淆名重建：`a`/`b2` 按类内容推断名字，没有证据就保留原名 |
| `src/emit/platform_builtin.c` | 内置平台构造器 / 抽象方法 / 方法签名表，不依赖 android.jar |
| `src/emit/stubs.c` | 为 APK 引用但没打包的类型生成桩声明 |
| `src/apk/axml.c` | 二进制 XML 解码器（AndroidManifest） |
| `src/formats/` | 可插拔格式 provider（dex / jvm / pyc / lua） |
| `bench/report.py` | 全量编译验证与错误分类；编译两遍，避免语法错误掩盖语义错误 |

设计取舍与踩过的坑记在 [DELIVERY.md](DELIVERY.md) 和
[PERFORMANCE.md](PERFORMANCE.md)。

## 目录

```
src/apk/        APK 容器、二进制 XML
src/common/     arena / buf / io / 线程池 / 写入器
src/dex/        DEX 解析
src/emit/       Java 生成、重映射、混淆名、平台依赖表、桩
src/formats/    多格式 provider
src/ir/         CFG、指令解码、方法体生成、解释器
bench/          基准与验证脚本
libs/           预编译引擎与调用接口
tests/          回归用例
```

## 构建

```sh
make run                        # 本机，产物 /tmp/tbuild/tachyon
make run OUT=/your/path         # 换输出位置

# 交叉编译成 Android 可直接执行的静态二进制
aarch64-linux-gnu-gcc -O2 -std=c11 -D_GNU_SOURCE -Isrc \
    -DTACHYON_VERSION='"0.3.0"' -static \
    -o libs/arm64-v8a/libtachyon.so \
    src/*.c src/*/*.c src/*/*/*.c -lpthread -lm
```

工作区挂载为 `noexec`，二进制必须放在可执行的位置（`/tmp`，或把 `libs/` 复制出去）。

## 验证

```sh
/tmp/tbuild/tachyon d app.apk -o /tmp/out
python3 bench/report.py /tmp/out      # 全量编译，报告写 /tmp/report/
```

## 文档

| 文件 | 内容 |
|---|---|
| [README-CN.md](README-CN.md) | 中文项目说明 |
| [USAGE.md](USAGE.md) | 全部命令与示例、输出结构、模式、进度协议、排错 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 分层、数据流、关键结构、线程模型、扩展点 |
| [SECURITY.md](SECURITY.md) | 威胁模型、防御措施、资源限制、Android 执行限制、供应链 |
| [DELIVERY.md](DELIVERY.md) | 能力清单与每个重要 bug 的根因 |
| [PERFORMANCE.md](PERFORMANCE.md) | 实测耗时、写盘下限、九个性能地雷 |
| [libs/README.md](libs/README.md) | 嵌入式引擎的调用接口 |

## 协议

未指定。使用前请与作者确认。
