#This package implements aggregation methods for epistatic statistics obtained for different null-models conditioned on phenotypes
package Phenotype::AggregateStatistics;
use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK $VERSION);
use Exporter;
$VERSION = 1.00; # Or higher
@ISA = qw(Exporter);
# Symbols to autoexport (:DEFAULT tag)
@EXPORT = qw(); 
@EXPORT_OK = qw();
use File::Path qw(make_path rmtree);
use SitePairMatrix;
use Time::Progress;
#sort_order: 0- ascending; 1- descending
sub get_best_stat{
	my ($sort_order,$s1,$s2)=@_;
	if(defined($s1)&&defined($s2)){
		if($sort_order==0){
			return ($s1<=$s2)?$s1:$s2;
		}
		return ($s1>=$s2)?$s1:$s2;
	}
	return defined($s1)?$s1:$s2;
}

sub find_missed_samples{
	my ($path,$ext,$ra_samples_storage_node)=@_;
	my @n;
	$path=~s/\s*$//;
	$path=~s/\/$//;
	$path.=$ra_samples_storage_node->[2]."/";
	my $from=$ra_samples_storage_node->[0];
	my $to=$ra_samples_storage_node->[1];
	for(my $i=$from;$i<=$to;$i++){
		my $str=$path.$i.$ext;
		if(-e $str){
			my $filesize=-s $str;
			if($filesize){
				last if(defined $n[1]);
				$n[0]++;
			}else{
				$n[1]++;
			}
		}else{
			$n[1]++;
		}
	};
	if (wantarray()) {
		# list context
		$n[0]+=$from;
		$n[1]+=$n[0]-1;
		return @n;
	}elsif (defined wantarray()) {
		return $n[1];
	}
	return undef;
}

sub get_random_index{
	my @probs=@_;
	die "\nThe function expects a vector of cumulative probabilities as an argument!" unless(sprintf("%.6f",$probs[-1])==1);
	my $k=0;
	if(@probs>1){
		my $smpl=rand;
		for(;$k<@probs;$k++){
			last if $smpl<$probs[$k];
		}
	}
	return $k;
}

sub aggregateByBest{
	my ($pairs_fn,$f_intragene,$indir,$ra_pheno_samles_dirs,$ra_samples_storage,$file_ext,
			$rh_bg_sites2pheno,$rh_fg_sites2pheno,$site2pheno_order,$outdir,$ntries)=@_;
	$ntries=1 unless defined $ntries;
	$indir=~s/\s+$//;
	$indir=~s/\/$//;
	$indir.="/";
	$outdir=~s/\s+$//;
	$outdir=~s/\/$//;
	my $sp_matrix=SitePairMatrix->new($pairs_fn,$f_intragene);
	my @bg_sites;
	my @fg_sites;
	$sp_matrix->get_sites(\@bg_sites,\@fg_sites);
	for(my $i=0;$i<@bg_sites;$i++){
		die "\nThe site $bg_sites[$i] is absent in the background site to phenotype map!" unless defined $rh_bg_sites2pheno->{$bg_sites[$i]};
	}
	for(my $i=0;$i<@fg_sites;$i++){
		die "\nThe site $fg_sites[$i] is absent in the background site to phenotype map!" unless defined $rh_fg_sites2pheno->{$fg_sites[$i]};
	}
	my $npairs=$sp_matrix->{NLINES};
	my $npheno=@{$ra_pheno_samles_dirs};
	my $nsamples=$ra_samples_storage->[-1]->[1]-$ra_samples_storage->[0]->[0]+1;
	my $progress_bar = Time::Progress->new(min => 1, max => $nsamples);
	die "\nNot allowed value for the 'site2pheno_order': $site2pheno_order!" unless ($site2pheno_order==0)||($site2pheno_order==1);
	my @pairs2pheno;
	for(my $i=0;$i<$npairs;$i++){
		my ($bgs,$fgs)=$sp_matrix->line2site_pair($i);
		my $p2p_val=$rh_bg_sites2pheno->{$bgs}->[0]*$rh_fg_sites2pheno->{$fgs}->[0];
		my @p2p_idx;
		push @p2p_idx,0;
		for(my $j=1;$j<$npheno;$j++){
			my $p2p_val2=$rh_bg_sites2pheno->{$bgs}->[$j]*$rh_fg_sites2pheno->{$fgs}->[$j];
			if(get_best_stat($site2pheno_order,$p2p_val,$p2p_val2)==$p2p_val2){
				if($p2p_val==$p2p_val2){
					push @p2p_idx,$j;
				}else{
					@p2p_idx=($j);
				}
				$p2p_val=$p2p_val2;
			}
		}
		push @pairs2pheno,[@p2p_idx];
	}
	for(my $j=0;$j<@{$ra_samples_storage};$j++){
		my $out_path=$outdir.$ra_samples_storage->[$j]->[2];
		make_path($out_path) unless(-d $out_path);
		for(my $I=0;$I<$ntries;$I++){
			my ($from,$to)=find_missed_samples($out_path,$file_ext,$ra_samples_storage->[$j]);
			last if $to<$from;
			for(my $k=$from;$k<=$to;$k++){
				my @aggregated;
				my @pairs2phen_idx;
				for(my $i=0;$i<$npairs;$i++){
					my $ridx=0;
					my $n=@{$pairs2pheno[$i]};
					$ridx=int rand($n) if $n>1;
					$ridx=$pairs2pheno[$i]->[$ridx];
					push @pairs2phen_idx,$ridx;
				}
				for(my $i=0;$i<$npheno;$i++){
					my $in_path=$indir.$ra_pheno_samles_dirs->[$i].$ra_samples_storage->[$j]->[2];
					my $fn=$in_path."/".$k.$file_ext;
					open INPF, "<$fn" or die "\nUnable to open input file: $fn!";
					my $pair_idx=0;
					while(<INPF>){
						if(/\S+/){
							$aggregated[$pair_idx]=$_ if $pairs2phen_idx[$pair_idx]==$i;
							$pair_idx++;
						}
					}
					close INPF;
				}
				my $fn=$out_path."/".$k.$file_ext;
				open OPF,">$fn" or die "\nUnable to open output file:$fn!";
				foreach my $line(@aggregated){
					print OPF $line;
				}
				close OPF;
				print STDERR $progress_bar->report("\r%20b  ETA: %E", $k);
			}
		}
	}
}

sub aggregateByMean{
	my ($pairs_fn,$f_intragene,$indir,$ra_pheno_samles_dirs,$ra_samples_storage,$file_ext,
			$rh_bg_sites2pheno,$rh_fg_sites2pheno,$site2pheno_order,$outdir,$ntries)=@_;
	$ntries=1 unless defined $ntries;
	$indir=~s/\s+$//;
	$indir=~s/\/$//;
	$indir.="/";
	$outdir=~s/\s+$//;
	$outdir=~s/\/$//;
	my $sp_matrix=SitePairMatrix->new($pairs_fn,$f_intragene);
	my @bg_sites;
	my @fg_sites;
	$sp_matrix->get_sites(\@bg_sites,\@fg_sites);
	for(my $i=0;$i<@bg_sites;$i++){
		die "\nThe site $bg_sites[$i] is absent in the background site to phenotype map!" unless defined $rh_bg_sites2pheno->{$bg_sites[$i]};
	}
	for(my $i=0;$i<@fg_sites;$i++){
		die "\nThe site $fg_sites[$i] is absent in the background site to phenotype map!" unless defined $rh_fg_sites2pheno->{$fg_sites[$i]};
	}
	my $npairs=$sp_matrix->{NLINES};
	my $npheno=@{$ra_pheno_samles_dirs};
	my $nsamples=$ra_samples_storage->[-1]->[1]-$ra_samples_storage->[0]->[0]+1;
	my $progress_bar = Time::Progress->new(min => 1, max => $nsamples);
	die "\nNot allowed value for the 'site2pheno_order': $site2pheno_order!" unless ($site2pheno_order==0)||($site2pheno_order==1);
	my @pairs2pheno;
	for(my $i=0;$i<$npairs;$i++){
		my ($bgs,$fgs)=$sp_matrix->line2site_pair($i);
		push @pairs2pheno,[];
		my $norm=0;
		for(my $j=0;$j<$npheno;$j++){
			my $val=$rh_bg_sites2pheno->{$bgs}->[$j]*$rh_fg_sites2pheno->{$fgs}->[$j];
			$norm+=$val;
			push @{$pairs2pheno[-1]},$val;
		}
		my $n=0;
		for(my $j=0;$j<$npheno;$j++){
			$pairs2pheno[-1]->[$j]/=$norm if $norm>0;
			if($site2pheno_order==0){
				$pairs2pheno[-1]->[$j]=1-$pairs2pheno[-1]->[$j];
				$n+=$pairs2pheno[-1]->[$j];
			}
		}
		if($site2pheno_order==0){
			for(my $j=0;$j<$npheno;$j++){
				$pairs2pheno[-1]->[$j]/=$n;
			}
		}
	}
	for(my $j=0;$j<@{$ra_samples_storage};$j++){
		my $out_path=$outdir.$ra_samples_storage->[$j]->[2];
		make_path($out_path) unless(-d $out_path);
		for(my $I=0;$I<$ntries;$I++){
			my ($from,$to)=find_missed_samples($out_path,$file_ext,$ra_samples_storage->[$j]);
			last if $to<$from;
			for(my $k=$from;$k<=$to;$k++){
				my @aggregate;
				for(my $i=0;$i<$npheno;$i++){
					my $in_path=$indir.$ra_pheno_samles_dirs->[$i].$ra_samples_storage->[$j]->[2];
					my $fn=$in_path."/".$k.$file_ext;
					open INPF, "<$fn" or die "\nUnable to open input file: $fn!";
					my $pair_idx=0;
					while(<INPF>){
						chomp;
						s/\s+$//;
						if(/\S+/){
							my @line=split "\t";
							$aggregate[$pair_idx]=[] unless defined $aggregate[$pair_idx];
							for(my $j=0;$j<@line;$j++){
								$aggregate[$pair_idx]->[$j]+=$line[$j]*$pairs2pheno[$pair_idx]->[$i];
								if($j){
									$aggregate[$pair_idx]->[$j]=sprintf("%.2f",$aggregate[$pair_idx]->[$j]);
								}else{
									$aggregate[$pair_idx]->[0]=sprintf("%.6f",$aggregate[$pair_idx]->[0]);
								}
							}
							$pair_idx++;
						}
					}
					close INPF;
					die "\nWrong number of lines in the file: $fn!" unless $npairs==$pair_idx;
				}
				my $fn=$out_path."/".$k.$file_ext;
				open OPF,">$fn" or die "\nUnable to open output file:$fn!";
				for(my $i=0;$i<$npairs;$i++){
					my $line=join("\t",@{$aggregate[$i]})."\n";
					print OPF $line;
				}
				close OPF;
				print STDERR $progress_bar->report("\r%20b  ETA: %E", $k);
			}
		}
	}
}

sub aggregateByMixture{
	my ($pairs_fn,$f_intragene,$indir,$ra_pheno_samles_dirs,$ra_samples_storage,$file_ext,
			$rh_bg_sites2pheno,$rh_fg_sites2pheno,$site2pheno_order,$outdir,$ntries)=@_;
	$ntries=1 unless defined $ntries;
	$indir=~s/\s+$//;
	$indir=~s/\/$//;
	$indir.="/";
	$outdir=~s/\s+$//;
	$outdir=~s/\/$//;
	my $alpha=0.5;
	my $sp_matrix=SitePairMatrix->new($pairs_fn,$f_intragene);
	my @bg_sites;
	my @fg_sites;
	$sp_matrix->get_sites(\@bg_sites,\@fg_sites);
	for(my $i=0;$i<@bg_sites;$i++){
		die "\nThe site $bg_sites[$i] is absent in the background site to phenotype map!" unless defined $rh_bg_sites2pheno->{$bg_sites[$i]};
	}
	for(my $i=0;$i<@fg_sites;$i++){
		die "\nThe site $fg_sites[$i] is absent in the background site to phenotype map!" unless defined $rh_fg_sites2pheno->{$fg_sites[$i]};
	}
	my $npairs=$sp_matrix->{NLINES};
	my $npheno=@{$ra_pheno_samles_dirs};
	my $nsamples=$ra_samples_storage->[-1]->[1]-$ra_samples_storage->[0]->[0]+1;
	my $p0=-log($alpha)/$nsamples;
	my $progress_bar = Time::Progress->new(min => 1, max => $nsamples);
	die "\nNot allowed value for the 'site2pheno_order': $site2pheno_order!" unless ($site2pheno_order==0)||($site2pheno_order==1);
	my @pairs2phen_probs;
	for(my $i=0;$i<$npairs;$i++){
		my ($bgs,$fgs)=$sp_matrix->line2site_pair($i);
		my @phen_probs;
		my $norm=0;
		for(my $j=0;$j<$npheno;$j++){
			my $val=$rh_bg_sites2pheno->{$bgs}->[$j]*$rh_fg_sites2pheno->{$fgs}->[$j];
			$norm+=$val;
			push @phen_probs,$val;
		}
		my $n=0;
		for(my $j=0;$j<$npheno;$j++){
			$phen_probs[$j]/=$norm if $norm>0;
			if($site2pheno_order==0){
				$phen_probs[$j]=$p0 unless $phen_probs[$j]>0;
				$phen_probs[$j]=1/$phen_probs[$j];
				$n+=$phen_probs[$j];
			}
		}
		if($site2pheno_order==0){
			for(my $j=0;$j<$npheno;$j++){
				$phen_probs[$j]/=$n;
			}
		}
		for(my $j=1;$j<$npheno;$j++){
			$phen_probs[$j]+=$phen_probs[$j-1];
		}
		push @pairs2phen_probs,[@phen_probs];
	}
	for(my $j=0;$j<@{$ra_samples_storage};$j++){
		my $out_path=$outdir.$ra_samples_storage->[$j]->[2];
		make_path($out_path) unless(-d $out_path);
		for(my $I=0;$I<$ntries;$I++){
			my ($from,$to)=find_missed_samples($out_path,$file_ext,$ra_samples_storage->[$j]);
			last if $to<$from;
			for(my $k=$from;$k<=$to;$k++){
				my @aggregated;
				my @pairs2phen_idx;
				for(my $i=0;$i<$npairs;$i++){
					my $ridx=get_random_index(@{$pairs2phen_probs[$i]});
					push @pairs2phen_idx,$ridx;
				}
				for(my $i=0;$i<$npheno;$i++){
					my $in_path=$indir.$ra_pheno_samles_dirs->[$i].$ra_samples_storage->[$j]->[2];
					my $fn=$in_path."/".$k.$file_ext;
					open INPF, "<$fn" or die "\nUnable to open input file: $fn!";
					my $pair_idx=0;
					while(<INPF>){
						if(/\S+/){
							$aggregated[$pair_idx]=$_ if $pairs2phen_idx[$pair_idx]==$i;
							$pair_idx++;
						}
					}
					close INPF;
				}
				my $fn=$out_path."/".$k.$file_ext;
				open OPF,">$fn" or die "\nUnable to open output file:$fn!";
				foreach my $line(@aggregated){
					print OPF $line;
				}
				close OPF;
				print STDERR $progress_bar->report("\r%20b  ETA: %E", $k);
			}
		}
	}
}


1;