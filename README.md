# vfox-python shorthand version fix

让 `vfox use python@3.12` 这种**大版本号**写法在 vfox-python 插件下正常工作。

针对 `version-fox/vfox-python` **v0.6.2**（2026-09-12 发布的最新 release，问题仍未修复），
在 **vfox 1.0.12 / Linux** 上实测有效；对 vfox 0.4～1.x 的其它版本应当同样适用（判定逻辑来自核心代码）。

```console
$ vfox use --global python@3.12
python@3.12 is not installed        ← 打补丁前

$ ./patch.sh && vfox use --global python@3.12
Preparing Python 3.12.14 for use...
Python 3.12.14 is healthy and ready to use
Now using python@3.12.14.           ← 打补丁后
```

## 现象

`vfox list` 明明装了 `3.12.14`，但用 `python@3.12` 切换会被拒绝；只有写全补丁号 `python@3.12.14` 才行。
nodejs / golang 等插件没有这个问题。

## 根因

vfox 核心的版本解析（`internal/sdk/sdk.go` 的 `preUse()`，1.0.12 在 469 行）规则是：

```go
if b.plugin.HasFunction("PreUse") {
    preUseResult, err := b.plugin.PreUse(preUseCtx)
    ...
    newVersion = preUseResult.Version      // 插件给什么就用什么
}

// 只有插件没给版本时，核心才做“精确匹配 + `版本.` 前缀匹配”
if newVersion == "" {
    ...
    prefix := version + "."
    for _, v := range installedVersions {
        if version == v { newVersion = v; break }
        if strings.HasPrefix(v, prefix) { newVersion = v; break }   // "3.12" -> "3.12.14"
    }
}
```

也就是说**大版本模糊匹配只在插件 PreUse 返回空版本时才会发生**。

而 vfox-python v0.6.2 的 `hooks/pre_use.lua` 在“没找到目标版本”的分支里把**请求的版本原样返回**了：

```lua
if not targetVersion then
    print("Warning: Target version " .. version .. " not found in installed versions")
    return {
        version = version        -- 返回 "3.12"，核心认为插件已解析完成，直接采用
    }
end
```

于是 `"3.12"` 被当成一个真实版本名往下走，核心那段前缀匹配根本没机会执行 → 报 “not installed”。

函数开头的 Windows 分支（`if OS_TYPE == "windows" then return { version = ctx.version } end`）
同样直接回传请求版本，所以按代码路径推断 Windows 上 `python@3.12` 也不会生效（**这条未在 Windows 上实测，只是读代码得到的结论**）。

顺带说明：`vfox use java@17` 失败是**另一个原因**，不是这个补丁要解决的——那是安装时用了裸大版本
（`vfox install java@17`），foojay 返回的版本名是 `17+35`，没有 `17.` 前缀可匹配。把安装版本写成
`java@17.0.18` 这类点分版本即可。

## 修复

`hooks/pre_use.lua` 在钩子内部自己完成大版本解析：先精确匹配，再按 `版本.` 前缀在已安装版本里取最高的，
匹配不到才把请求交回核心（`return ""`）。Windows 分支也走同一个解析。

这样除了让大版本生效，还保留了一个重要行为：**解析出的版本仍然会经过插件原有的 shebang 健康检查/自动修复**；
如果只是简单地把未命中分支改成 `return ""`，大版本切换虽然能成，但会跳过那段健康检查。

```lua
local function resolveInstalledVersion(version, installedSdks)
    if version == nil or installedSdks == nil then return nil end
    if installedSdks[version] ~= nil then return version end

    local prefix = version .. "."
    local best = nil
    for name in pairs(installedSdks) do
        if type(name) == "string" and name:sub(1, #prefix) == prefix then
            if best == nil or compare_versions(name, best) > 0 then best = name end
        end
    end
    return best
end
```

`compare_versions` 是插件 `lib/util.lua` 自带的函数，没有引入新依赖。

## 用法

```bash
git clone https://github.com/fuuhoo/vfox-python-shorthand-fix.git
cd vfox-python-shorthand-fix

./patch.sh                # 修补 $VFOX_HOME/plugin/python/hooks/pre_use.lua
./patch.sh --check        # 只判断是否已修，exit 0 = 已修
./patch.sh --restore      # 还原成上游原版
./patch.sh /path/to/pre_use.lua   # 显式指定文件（Docker 构建里很好用）
```

脚本是幂等的，第一遍会把原文件备份为 `pre_use.lua.orig`；如果目标文件里没有 `PLUGIN:PreUse`，它会拒绝覆盖，
以免将来插件重构后被静默破坏。

不想用脚本，也可以直接打上 diff（在插件根目录执行）：

```bash
patch -p1 < upstream.diff
```

Docker 构建阶段修补（本项目 `test.sh` 就是这么跑的）：

```dockerfile
COPY . /opt/shorthand-fix
RUN /opt/shorthand-fix/patch.sh "$VFOX_HOME/plugin/python/hooks/pre_use.lua"
```

## 验证

`./test.sh` 会启动一个装有 vfox + python 插件 + 两个 python 补丁版本的容器，先用**上游原版**复现问题，
再打补丁复验（文件用 `docker cp` 拷进去，不用 bind mount，避开 macOS 的文件共享限制）：

```console
$ ./test.sh
=== 1. upstream v0.6.2: shorthand is refused, full version works
PASS  3.9.25 -> 3.9.25   (full version switches)
PASS  3.12.14 -> 3.12.14   (full version switches)
PASS  3.12 -> 3.9.25   (shorthand rejected -> stays put (the bug))
PASS  3.9 -> 3.12.14   (shorthand rejected -> stays put (the bug))
=== 3. fixed hook: shorthand resolves to the installed patch version
PASS  3.12 -> 3.12.14   (python@3.12)
PASS  3.9 -> 3.9.25   (python@3.9)
=== 4. a shorthand with nothing installed stays refused
PASS  3.11 -> 3.12.14   (python@3.11 not installed -> no silent switch)
=== 5. the hook still runs the shebang health check
PASS  health check ran
=== 6. --restore
PASS  hook back to upstream bytes
all checks passed
```

`RUN_PLATFORM=linux/amd64 ./test.sh` 在同一台机器上交叉验证 amd64。
默认 harness 镜像是 `registry.cn-qingdao.aliyuncs.com/fubin/vfox-full:1.0.12`（自带 python 3.9.25 + 3.12.14），
`./test.sh <你的镜像>` 可换；只要求镜像里 `vfox list` 能看到两个不同小版本的 python。

## 给上游提 PR

`upstream.diff` 就是相对 v0.6.2 的完整改动，可直接作为 Pull Request 内容；
`upstream/pre_use.lua.0.6.2` 是原始文件，方便自行比对。

## 许可

Apache-2.0，与 `version-fox/vfox-python` 一致。`upstream/pre_use.lua.0.6.2` 与 `hooks/pre_use.lua`
是上游文件的副本/衍生修改，版权归 version-fox 项目所有。
