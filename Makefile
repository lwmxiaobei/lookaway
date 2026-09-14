.PHONY: build test app run stop selftest debug-overlay trace install clean

build:
	swift build

test:
	swift test

## 打包成 build/mac-duo.app（带 Info.plist 与签名）
app:
	./scripts/bundle.sh

## 停掉正在运行的实例。open 无法给已在运行的 App 传环境变量，
## 所以每个启动 target 都得先停干净。
stop:
	@-pkill -f "mac-duo.app/Contents/MacOS/MacDuo" 2>/dev/null || true
	@sleep 1

## 打包并启动。必须走 open：直接执行 bundle 内的二进制时，
## TCC 会把终端当作负责进程、查不到 NSMotionUsageDescription 而杀掉进程。
run: app stop
	open build/mac-duo.app

## 启动后自动预览一次遮罩，用来在没有 AirPods 时验证遮罩链路
selftest: app stop
	open build/mac-duo.app --env MACDUO_SELFTEST=1

## 诊断多屏：每块屏涂不同颜色并标注编号，遮 15 秒
debug-overlay: app stop
	open build/mac-duo.app --env MACDUO_DEBUG_OVERLAY=1 --env MACDUO_SELFTEST=1 --env MACDUO_SELFTEST_SECONDS=15

## 记录姿态轨迹到 /tmp/macduo-trace.csv，用来诊断零点和误触发
trace: app stop
	open build/mac-duo.app --env MACDUO_TRACE=1

## 装到 /Applications 并启动
install: app stop
	rm -rf /Applications/mac-duo.app
	cp -R build/mac-duo.app /Applications/
	open /Applications/mac-duo.app

clean:
	rm -rf .build build
