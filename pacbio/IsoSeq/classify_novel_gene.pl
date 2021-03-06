#!/usr/bin/perl -w
use strict;
use Data::Dumper;
use List::Util qw /sum/;

=pod 

USAGE: classify_novel_gene.pl  < ref_gff > < bam_file > < seq_fa >  < output_prefix >

=cut

die `pod2text $0 ` unless @ARGV==4;


open IN,"<$ARGV[0]" or die $!;
print STDERR "reading  reference gtf or gff file : $ARGV[0] ... \n";
my $gtf=  $ARGV[0]=~/gtf$/ ? 'gtf' : $ARGV[0]=~/gff\d?$/ ? 'gff' : 'unknown';
my (%ref_gff,$ref_gene,$ref_isoform,%gene);
my $exon=1;
while(<IN>){
	chomp;
	next if /^#/;
	my @F=split /\t/;
	my ($id ,$parent );
	if( $gtf eq 'gff' ){
		if($F[2] eq 'mRNA'){
			($ref_isoform) = $F[-1]=~/ID=([^;]+)/;
			($ref_gene)= $F[-1] =~/Parent=([^;]+)/;
			$exon=1;
			next;
		}elsif($F[2] eq 'exon'){
			$id=$ref_isoform;
			$parent=$ref_gene;
		}elsif($F[2] eq 'gene'){
			my ($g)= $F[-1]=~/ID=([^;]+)/;
			$gene{$F[0]}{$g}{start}=$F[3];
			$gene{$F[0]}{$g}{end}=$F[4];
			next;
		}else{
			next;
		}
	}elsif($gtf eq  'gtf' ){
		next unless $F[2] eq 'exon';
		($id)= $F[-1]=~/transcript_id \"([^"]+\")/;
		($parent)= $F[-1]=~/gene_id \"([^"]+)\"/;
	}else{
		die "can not recognise gtf or gff file : $ARGV[0] ! \n";
	}
	$ref_gff{ $F[0] }{ $parent }{ $id }{start}{ $F[3] }{ $exon }++;
	$ref_gff{ $F[0] }{ $parent }{ $id }{end}{ $F[4] }{ $exon }++;
	$ref_gff{ $F[0] }{ $parent }{ $id }{exon}{ $exon }++;
	$ref_gff{ $F[0] }{ $parent }{ $id }{strand}=$F[6];
	$exon++;
}
close IN;


my %flag=(
	1 => 'Same',
	2 => 'Patial',
	3 => 'Novel_Isoforms',
	4 => 'Overlap',
	5 => 'Pac_Exon_In_Ref_Intron',
	6 => 'Ref_Exon_In_Pac_Intron',
	7 => 'Overlap_Opposite',
	8 => 'Novel_Gene',
	9 => 'Exclusive',
	10 => 'Cross_Gene',
);

my (%bed,%pos,%map,%annot,%count);
print STDERR "transform  bam file < $ARGV[1] > to bed file < $ARGV[1].bed > ... \n"; 
system "bedtools  bamtobed  -bed12  -i $ARGV[1] >$ARGV[1].bed";
open IN,"<$ARGV[1].bed" or die $!;
print STDERR "reading bed file : $ARGV[1].bed ... \n";
while(<IN>){
	chomp;
	my @F=split /\t/;
	my $match_length= sum ( split /,/,$F[10] );
	my ($length)= $F[3]=~ /(\d+)_[\-\d]+kb$/;
	my $ratio= $match_length/$length ;
	my $n= ++$count{$F[3]};
	my @start= map{ $_+1+$F[1] } split /,/,$F[11];
	my @len = split /,/,$F[10];
	my @end;
	for my $i(0 .. $#start){
		$end[$i]=$start[$i]+$len[$i]-1;
	}	
	my %tmp= map{ $start[$_] => $end[$_] } 0 .. $#start;
	$bed{$F[3]}{$n}{pos}= \%tmp;
	$bed{$F[3]}{$n}{strand}=$F[5];
	$bed{$F[3]}{$n}{min}=$F[1]+1 ;
	$bed{$F[3]}{$n}{max}=$F[2]  ;
	$bed{$F[3]}{$n}{ratio}=$ratio  ;
	$bed{$F[3]}{$n}{chr}=$F[0]  ;
	
}
close IN;


print STDERR "classifying ... \n";
for my $seq(keys %bed){
	my @num= keys %{$bed{$seq}};
	my $max_ratio=0;
	for my $n(@num){
		$max_ratio= $bed{$seq}{$n}{ratio} if $bed{$seq}{$n}{ratio} > $max_ratio;
	}
	for my $num(@num){
		next if($max_ratio >= 0.1 and $bed{$seq}{$num}{ratio}<0.1 );
		my $chr=$bed{$seq}{$num}{chr};
		my $min=$bed{$seq}{$num}{min};
		my $max=$bed{$seq}{$num}{max};
		my $strand=$bed{$seq}{$num}{strand};
		my $exon_num= scalar keys %{$bed{$seq}{$num}{pos}};
		$map{$seq}{$num}={
			type => 8,
			gene => '.',
			transcript => '.',
		};
		my %num;
		my @s1= sort {$a<=>$b} keys %{$bed{$seq}{$num}{pos}};
		my @e1= sort {$a<=>$b} values %{$bed{$seq}{$num}{pos}};
		my @genes=sort { $gene{$chr}{$a}{start} <=> $gene{$chr}{$b}{start} } keys %{$gene{$chr}};
		for my $gene(@genes){
			my $gene_min=$gene{$chr}{$gene}{start};
			my $gene_max=$gene{$chr}{$gene}{end};
			next if $gene_max < $min;
			last if $gene_min > $max;
			my $n=0;
			for my $start ( @s1 ){
				$n++;
				my $end=$bed{$seq}{$num}{pos}{$start};
				for my $t(keys %{$ref_gff{$chr}{$gene}}){
					if( $ref_gff{$chr}{$gene}{$t}{start}{$start} && $ref_gff{$chr}{$gene}{$t}{end}{$end} or $exon_num >1 && $n==1 && $ref_gff{$chr}{$gene}{$t}{end}{$end}  or  $exon_num>1 && $n==$exon_num  && $ref_gff{$chr}{$gene}{$t}{start}{$start} ){
						$num{$gene}{$t}++;
					}
				}
			}
		}
		LABEL:
		for my $gene(keys %num){
			for my $t(keys %{$num{$gene}}){
				my $ref_num=keys %{$ref_gff{$chr}{$gene}{$t}{exon}};
				if($exon_num == $num{$gene}{$t} and $strand eq $ref_gff{$chr}{$gene}{$t}{strand} ){
					if($exon_num==$ref_num){
						$map{$seq}{$num}={
							type => 1,
							gene => $gene,
							transcript => $t,
						};
						last LABEL;
					}else{
						$map{$seq}{$num}={
							type => 2,
							gene => $gene,
							transcript => $t,
						};
					}
				}elsif($num{$gene}{$t} >0 and $strand eq $ref_gff{$chr}{$gene}{$t}{strand} and $map{$seq}{$num} > 3){
					$map{$seq}{$num}={
						type => 3,
						gene => $gene,
						transcript => '.',
					};
				}else{
					my @s2= sort {$a<=>$b} keys %{$ref_gff{$chr}{$gene}{$t}{start}};
					my @e2= sort {$a<=>$b} keys %{$ref_gff{$chr}{$gene}{$t}{end}};
					my $overlap= &overlap(\@s1,\@e1,\@s2,\@e2,$strand,$ref_gff{$chr}{$gene}{$t}{strand} );
					if($overlap < $map{$seq}{$num}{type}){
						$map{$seq}{$num}={
							type => $overlap,
							gene => $gene,
							transcript => '.',
						};
					}
				}
			}
		}
	}
}

print STDERR "reading seqence fa file : $ARGV[2] ... \n";
open IN,"<$ARGV[2]" or die $!;
local $/="\n>";
my %seq;
while(<IN>){
	chomp;
	s/^>//;
	my @F=split /\n/,$_,2;
	$seq{$F[0]}=$F[1];
}
close IN;
local $/="\n";

print STDERR "getting output ... \n";
open OUT1,">$ARGV[3].txt" or die $!;
print OUT1 "#SeqID\tRef_Gene\tRef_Transcript\tType\tStrand\tSequence\n";
open OUT2,">$ARGV[3].stat" or die $!;
print OUT2"Type\tCount\tPercent(%)\n";

my %stat;
my $total=0;
for my $seq(keys %map){
	my @num= keys %{$map{$seq}};
	my ($g,$t,$type,%g,$tmp,$strand);
	for my $n(@num){
		$strand=$bed{$seq}{$n}{strand} ;
		my $gene=$map{$seq}{$n}{gene};
		if( $gene  ne '.'){
			$g{$gene}++;
			if(!$type or $type > $map{$seq}{$n}{type} ){
				$type= $map{$seq}{$n}{type};
				$t= $map{$seq}{$n}{transcript};
				$tmp=$n ;
			}
		}
	}
	if(keys %g==0){
		$g='.';
		$t='.';
		$type= 8;
	}elsif( keys %g==1){
		$g=$map{$seq}{$tmp}{gene};
	}else{
		$g=join ",", keys %g;
		$t=".";
		$type=10;
	}
	$stat{$type}++;
	$total++;
	print OUT1 "$seq\t$g\t$t\t$flag{$type}\t$strand\t$seq{$seq}\n";
}

system "samtools view -f 4 $ARGV[1] | cut -f 1 >$ARGV[1].tmp";
open IN,"$ARGV[1].tmp" or die $!;
while(<IN>){
	chomp;
	print OUT1 "$_\t.\t.\tExclusive\t.\t$seq{$_}\n";
	$total++;
	$stat{9}++;
}
close IN;
unlink "$ARGV[1].tmp";
close OUT1;

for my $type(sort {$a<=>$b}keys %stat){
	$stat{$type}=0 unless $stat{$type};
	printf OUT2 "%s\t%d\t%.2f\n",$flag{$type},$stat{$type},100*$stat{$type}/$total;
}
close OUT2;

print STDERR "plotting ... \n";
open OUT,">__$$.R" or die $!;
print OUT <<R;
library("plotrix")
dat <- read.csv("$ARGV[3].stat",sep="\\t")
pdf("$ARGV[3].pdf")
n <- nrow(dat)
mycol <- rainbow(n)
pie3D(dat\$Count,radius=1.5,height=0.2,theta=pi/6,start=0,border=par('fg'), col=mycol,labels= paste(dat\$Percent,"%",sep=""),labelpos=NULL,labelcol=par("fg"),labelcex=1.5,  sector.order=NULL,explode=0.2,shade=0.8,mar=c(4,4,10,4),pty="s" )
legend('topright',legend=dat\$Type,xpd=T,col=mycol,fill=mycol,inset=-0.2,box.col="white" )
dev.off()
png("$ARGV[3].png")
pie3D(dat\$Count,radius=1.5,height=0.2,theta=pi/6,start=0,border=par('fg'), col=mycol,labels= paste(dat\$Percent,"%",sep=""),labelpos=NULL,labelcol=par("fg"),labelcex=1.5,  sector.order=NULL,explode=0.2,shade=0.8,mar=c(4,4,10,4),pty="s" )
legend('topright',legend=dat\$Type,xpd=T,col=mycol,fill=mycol,inset=-0.2,box.col="white" )
dev.off()

R

system "Rscript  __$$.R";
unlink "__$$.R";

print STDERR "completed !\n";

sub overlap{
	my ($s1,$e1,$s2,$e2,$strand1,$strand2)=@_;
	for my $i(0 .. $#$s1){
		for my $j(0 .. $#$s2){
			if($s1->[$i] < $e2->[$j]  and $e1->[$i] > $s2->[$j] ){
				return 4 if($strand1 eq $strand2);
				return 7 if($strand1 ne $strand2);
			}
		}
	}
	if($s1<$s2 and $e1 > $e2){
		return 6;
	}elsif($s1 > $s2 and $e1 < $e2){
		return 5;
	}else{
		return 8; 
	}
}





