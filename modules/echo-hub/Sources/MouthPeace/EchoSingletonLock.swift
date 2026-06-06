import Darwin
import Foundation

final class EchoSingletonLock {
   private let fileDescriptor: Int32

   private init(fileDescriptor: Int32) {
      self.fileDescriptor = fileDescriptor
   }

   static func acquire() -> EchoSingletonLock? {
      var filename = "com.douglastalley.MouthPeace.singleton.lock"
      let env = ProcessInfo.processInfo.environment
      if env["MOUTHPEACE_DISABLE_SETTINGS_PERSISTENCE"] == "1",
         let testLockId = env["MOUTHPEACE_UNSAFE_TEST_SINGLETON_LOCK_ID"],
         !testLockId.isEmpty
      {
         filename = "com.douglastalley.MouthPeace.singleton.\(testLockId).lock"
      }
      let path = (NSTemporaryDirectory() as NSString).appendingPathComponent(filename)
      let fd = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
      guard fd >= 0 else { return nil }

      guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
         close(fd)
         return nil
      }

      _ = ftruncate(fd, 0)
      if let payload = "\(getpid())\n".data(using: .utf8) {
         payload.withUnsafeBytes { bytes in
            _ = write(fd, bytes.baseAddress, bytes.count)
         }
      }
      return EchoSingletonLock(fileDescriptor: fd)
   }

   deinit {
      flock(fileDescriptor, LOCK_UN)
      close(fileDescriptor)
   }
}
