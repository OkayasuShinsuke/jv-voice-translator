import Foundation

/// マイクの生データを、今エンジンに渡してよいかどうかを決める、純粋なSwiftの状態。
///
/// たとえ話:マイクの前に置く「シャッター」。閉じている間も音自体はマイクに入り続けるが、
/// その先の認識エンジンには何も届かなくなる。エンジンを完全に止めたり作り直したりしないので、
/// 再開もすぐにできる。
///
/// Apple のフレームワークを一切使わない「判定だけ」の部品なので、マイクが無い環境でもテストできる。
public struct MicGate: Sendable, Equatable {
    public private(set) var isPaused: Bool = false

    public init() {}

    public mutating func pause() {
        isPaused = true
    }

    public mutating func resume() {
        isPaused = false
    }

    /// 今この音をエンジンに渡してよいか。
    public var shouldForwardAudio: Bool { !isPaused }
}
