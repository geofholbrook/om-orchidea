(in-package om)

(defvar *config-template-path*
        (make-pathname :directory (pathname-directory *executable-path*)
                   :name "config_template.txt")) 

(defun set-executable-path ()
    (setf *executable-path* (om::file-chooser)))

(defvar *db-file* nil)
(defvar *sound_path* nil)

(defun set-db-file ()
  (setf *db-file* (om::file-chooser)))

(defun list-join (lis delimiter) 
  (format nil (string+ "~{~A~^" delimiter "~}") lis))

(defun escape-slashes (str) 
  (let ((new-char-list '()))
    (coerce (mapcan #'(lambda (char)                
                        (if (eql char #\/) (list #\\ #\/) (list char)))
                    (coerce str 'list))
            'string)))
    
(defun orchestrate (sound orch-string dynamic)
  (when (null *db-file*) (error "db file not set, use set-db-file function"))
    (let ((tmp-dir (make-pathname :directory (append (pathname-directory *om-tmpfiles-folder*) (list (string+ "tmp-" (prin1-to-string (om-random 10000000 99999999)))))))
          (db-sound-path (derive-sound-path-from-db-file))
          (output-file (string+ (pathname-name (filename sound)) "-orch-" (prin1-to-string (om-random 10000000 99999999)) ".wav")))

      (om-cmd-line (string+ 
                    "mkdir " (namestring tmp-dir)
                    " && "
                    "cd " (namestring tmp-dir)
                    " && "
                    "sed 's/__DB_FILE__/" (escape-slashes (namestring *db-file*)) "/' " (namestring *config-template-path*) " > orch.txt"
                    " && "
                    "sed -i '' 's/__SOUND_PATH__/" (escape-slashes (namestring db-sound-path)) "/' orch.txt"
                    " && "
                    "sed -i '' 's/__ORCHESTRA__/" orch-string "/' orch.txt"
                    " && "
                    "sed -i '' 's/__ONSETS_THRESHOLD__/" (if dynamic "0.1" "2") "/' orch.txt"
                    " && "
                    (namestring *executable-path*) " " (namestring (filename sound)) " orch.txt"
                    " && mv connection.wav ../" output-file " && cd .. && rm -rf " (namestring tmp-dir)
))
     
      (tmpfile output-file)))

(defun derive-sound-path-from-db-file ()
  (let ((root (first (lw::split-sequence (list #\.) (pathname-name *db-file*)))))
    (make-pathname :directory (append (pathname-directory *db-file*) (list root)))))