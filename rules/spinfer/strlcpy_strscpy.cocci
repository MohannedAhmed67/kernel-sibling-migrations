@@
expression E0, E1, E2;
@@
- strlcpy(E0, E1, E2); 
+ strscpy(E0, E1, E2); 
// Infered from: (19/{before.c,after.c}: snd_seq_ioctl_get_queue_info), (18/{before.c,after.c}: snd_seq_oss_synth_probe), (18/{before.c,after.c}: snd_seq_oss_synth_make_info), (18/{before.c,after.c}: snd_seq_oss_synth_make_info), (17/{before.c,after.c}: snd_seq_oss_midi_check_new_port), (17/{before.c,after.c}: snd_seq_oss_midi_make_info), (16/{before.c,after.c}: snd_rawmidi_new), (15/{before.c,after.c}: snd_pcm_info), (15/{before.c,after.c}: snd_pcm_info), (15/{before.c,after.c}: snd_pcm_info), (14/{before.c,after.c}: _snd_pcm_new), (13/{before.c,after.c}: snd_mixer_oss_info), (13/{before.c,after.c}: snd_mixer_oss_info), (13/{before.c,after.c}: snd_mixer_oss_info_obsolete), (13/{before.c,after.c}: snd_mixer_oss_info_obsolete), (13/{before.c,after.c}: snd_mixer_oss_test_id), (13/{before.c,after.c}: snd_mixer_oss_notify_handler), (12/{before.c,after.c}: snd_card_new), (12/{before.c,after.c}: snd_card_set_id_no_lock), (11/{before.c,after.c}: snd_hwdep_info), (11/{before.c,after.c}: snd_hwdep_info), (11/{before.c,after.c}: snd_hwdep_new), (10/{before.c,after.c}: get_available_index), (09/{before.c,after.c}: snd_ctl_new1), (09/{before.c,after.c}: snd_ctl_card_info), (09/{before.c,after.c}: snd_ctl_card_info), (09/{before.c,after.c}: snd_ctl_card_info), (09/{before.c,after.c}: snd_ctl_card_info), (09/{before.c,after.c}: snd_ctl_card_info), (09/{before.c,after.c}: snd_ctl_card_info), (09/{before.c,after.c}: snd_ctl_enum_info), (08/{before.c,after.c}: snd_compress_set_id), (07/{before.c,after.c}: pxa2xx_ac97_probe), (06/{before.c,after.c}: aaci_init_card), (06/{before.c,after.c}: aaci_init_card), (06/{before.c,after.c}: aaci_init_pcm), (05/{before.c,after.c}: modalias_show), (04/{before.c,after.c}: layout_attached_codec), (04/{before.c,after.c}: layout_attached_codec), (04/{before.c,after.c}: layout_attached_codec), (03/{before.c,after.c}: aoa_alsa_init), (03/{before.c,after.c}: aoa_alsa_init), (03/{before.c,after.c}: aoa_alsa_init), (03/{before.c,after.c}: aoa_alsa_init), (02/{before.c,after.c}: toonie_init), (01/{before.c,after.c}: tas_i2c_probe), (00/{before.c,after.c}: onyx_i2c_probe)
// Recall: 1.00, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
// Final metrics (for the combined 1 rules):
// -- Edit Location --
// Recall: 1.00, Precision: 1.00
// -- Node Change --
// Recall: 1.00, Precision: 1.00
// -- General --
// Functions fully changed: 30/30(100%)


// ---------------------------------------------
