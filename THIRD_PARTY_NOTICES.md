# 第三方代码声明

本项目在某些系统指标读取的实现上参考/改编了开源项目 **Stats**：

- 项目：Stats
- 仓库：<https://github.com/exelban/stats>
- 作者：Serhiy Mytrovtsiy
- 许可证：MIT

## 具体派生范围

| 本项目文件 | 参考的上游文件 | 内容 |
| --- | --- | --- |
| `Sources/Metrics/SMCCore.swift` | `SMC/smc.swift` | AppleSMC 用户客户端的数据结构布局、命令码（readKeyInfo / readBytes / readIndex）、`IOConnectCallStructMethod` 调用方式，以及 `sp78`/`sp5a`/`sp87`/`flt`/`fpe2`/`ui*` 等数值类型的解码方式 |
| `Sources/Metrics/SystemReaders.swift` | `Modules/CPU/readers.swift`、`Modules/RAM/readers.swift`、`Modules/GPU/reader.swift`、`Modules/Net/readers.swift` | CPU tick 差分统计、`vm_statistics64` 已用内存公式（`active + inactive + speculative + wired + compressed − purgeable − external`）、`IOAccelerator` 的 `Device Utilization %` 键名、`NET_RT_IFLIST2` + `if_msghdr2` 读取收发字节的思路 |
| `Sources/Metrics/ThermalReader.swift` | `Modules/Sensors/readers.swift` | 枚举全部温度键并按数值范围过滤无效传感器的思路（键名分类为本项目自行实现的动态方案） |
| `Sources/Metrics/ProcessSampler.swift` | `Modules/GPU/reader.swift`、`Modules/RAM/readers.swift` | 通过 IOAccelerator 子节点的 `IOUserClientCreator` + `AppUsage[].accumulatedGPUTime` 计算每进程 GPU 占用；用私有函数 `responsibility_get_pid_responsible_for_pid` 把辅助进程归并到所属应用的思路 |
| `Sources/Metrics/NetworkProcessMonitor.swift` | `Modules/Net/readers.swift` | 调用 `/usr/bin/nettop -P -L 1 -n` 解析每进程收发字节、做差得到速率的做法 |

上游项目中与本项目无关的部分（风扇控制特权助手、图表、更新器、LevelDB、菜单栏 UI 等）均未使用。

## 为什么这样做是合规的

MIT 许可证允许使用、修改、再分发甚至闭源商用，唯一要求是**保留版权声明和许可声明**。
因此本项目：

1. 在本文件中完整保留 Stats 的 MIT 许可证原文；
2. 在每个参考了上游实现的源文件顶部注明出处；
3. 本项目自身同样以 MIT 许可证发布。

## Stats 的 MIT 许可证原文

```
MIT License

Copyright (c) 2019 Serhiy Mytrovtsiy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
