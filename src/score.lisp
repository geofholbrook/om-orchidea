(in-package om)

(defun orch-output->chord-seq (orch-output)     
  (make-instance 'chord-seq 
                 :lmidic (mapcar #'(lambda (segment) 
                                     (solution->chord (orch-solution-notes 
                                                       (car (orch-segment-solutions segment)))
                                                      (orch-output-orchestration orch-output))) 
                                 (orch-output-segments orch-output))
                 :lonset (mapcar #'orch-segment-onset-ms (orch-output-segments orch-output))))

(defun solution->chord (notes orchestration)
  (let ((channels
         (loop with used-channels = '() 
               for note in notes
               for channel = (loop for sym in orchestration
                                   for ch from 1
                                   when (and (equal (orch-note-instrument note) sym)
                                             (not (find ch used-channels)))
                                   return ch)
               do (push channel used-channels)
               collect channel)))
      
    (make-instance 'chord 
                   :lmidic (mapcar #'(lambda (note) 
                                       (+ (n->mc (orch-note-pitch-name note)) (orch-note-detune note)))
                                   notes)
                   :lchan channels)))


;; reference: (midi-number (pitch) , onset-time(ms), duration(ms), velocity, channel)

(defun orch-output->mf-info (orch-output)
  (correct-channels (sort (mapcan #'(lambda (segment) 
                    (mapcar #'(lambda (note) 
                                (note->mf-note note (orch-segment-onset-ms segment) (orch-output-orchestration orch-output)))
                            (orch-solution-notes (car (orch-segment-solutions segment)))))
                (orch-output-segments orch-output))
        #'< 
        :key #'second)))

(defun correct-channels (mf-info)
  "corrects simultaneous notes on the same channel by getting the next available channel. Provided the overlap is caused by adjacent instruments with the same name, and overlaps have been avoided already in previous steps (like, in the orchidea executable) then this should work fine."
  (loop with notes-playing = '()
        for note in mf-info
        for new-channel = (loop for chan from (fifth note)
                                when (not (find chan (mapcar 'fifth notes-playing)))
                                return chan)
        for corrected-note = `(,@(subseq note 0 4) ,new-channel)
        do (setf notes-playing
                 (append (remove-if #'(lambda (np) (<= (+ (second np) (third np)) (second note)))
                                    notes-playing)
                         (list corrected-note)))
        collect corrected-note))

(defun note->mf-note (note onset orchestration)
  (list (* (n->mc (orch-note-pitch-name note)) 0.01)
               onset
               (orch-note-duration-ms note)
               (get-velocity-from-orch-note-dynamic (orch-note-dynamic note))
               (1+ (position (orch-note-instrument note) orchestration))))
        
(defun get-velocity-from-orch-note-dynamic (dynamic) 
  (or (get-vel-from-dyn (intern (string-upcase dynamic) :keyword))
      (progn ()
        (print (string+ "using fallback velocity 64, none found for: " dynamic))
        64)))

(defun orch-output->multi-seq (orch-output)
  (mf-info->multi-seq (orch-output->mf-info orch-output)))

(defun mf-info->multi-seq (mf-info)
  (let ((grouped (sort (group-by mf-info 'fifth)
                       #'<
                       :key #'car)))
    (make-instance 'multi-seq
                   :chord-seqs (mapcar #'(lambda (entry) 
                                           (let ((zipped (mat-trans (cdr entry))))
                                             (make-instance 'chord-seq
                                                            :lmidic (om* (first zipped) 100)
                                                            :lonset (second zipped)
                                                            :ldur (third zipped)
                                                            :lvel (fourth zipped)
                                                            :lchan (fifth zipped))))

                                       grouped))))

(defun group-by (lis fn)
  (reduce #'(lambda (result elt)
              (let ((group-key (funcall fn elt)))
                (unless (find-if #'(lambda (entry) (equal (car entry) group-key))
                                 result)
                  (push `(,group-key . ()) result))
                (push elt (cdr (assoc group-key result)))
                result))
          lis
          :initial-value nil))


;;; quantization -> poly object

(defun orch-output->poly (orch-output quantizer)
  (let* ((multi-seq (orch-output->multi-seq orch-output)))
     (multi-seq-quantize multi-seq quantizer)))

(defun multi-seq-quantize (multi-seq quantizer)
  (print (length (chord-seqs multi-seq)))
  (let* ((onsets (sort. (reduce 'union (mapcar #'lonset (chord-seqs multi-seq)))))
         (shifted (om- onsets (car onsets)))
         (durations (x->dx shifted))
         (quant-fn (or quantizer #'(lambda (durations) (omquantify durations 60 '(4 4) 8))))
         (tree (funcall quant-fn durations))
         (ratios (tree2ratio tree)))
    (let ((encoded-rhythms 
          (mapcar #'(lambda (cseq) (rhythm-as-segments 
                                    (om- (lonset cseq) (car onsets)) 
                                    (ldur cseq) 
                                    shifted)) 
                  (chord-seqs multi-seq))))
      (mki 'poly
           :voices (loop for rhythm in encoded-rhythms
                         for cseq in (chord-seqs multi-seq)
                         collect
                         (let ((ratios-with-rests
                                (loop for ratio in ratios
                                      for index from 0
                                      collect (* ratio
                                                 (if (find index (mapcar 'first rhythm))
                                                     1
                                                   -1)))))
                           (make-instance 'voice
                                          :tree (mktree ratios-with-rests '(4 4))
                                          :chords (inside cseq))))))))
                                      
                                

(defun rhythm-as-segments (onsets durations all-onsets)
  ;;; this is a bit tricky. return list of pairs: (<segment-index> <duration-in-segments>)
  ;;; allow for inaccuracy of duration
  (loop for onset in onsets
        for segment-index = (position onset all-onsets)
        collect (list segment-index 1) ;;; TODO get duration in segments
        ))
    

                    